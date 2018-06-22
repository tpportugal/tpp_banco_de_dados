# == Schema Information
#
# Table name: current_routes
#
#  id                                 :integer          not null, primary key
#  onestop_id                         :string
#  name                               :string
#  tags                               :hstore
#  operator_id                        :integer
#  created_or_updated_in_changeset_id :integer
#  version                            :integer
#  created_at                         :datetime
#  updated_at                         :datetime
#  geometry                           :geography({:srid geometry, 4326
#  vehicle_type                       :integer
#  color                              :string
#  edited_attributes                  :string           default([]), is an Array
#  wheelchair_accessible              :string           default("unknown")
#  bikes_allowed                      :string           default("unknown")
#
# Indexes
#
#  c_route_cu_in_changeset                        (created_or_updated_in_changeset_id)
#  index_current_routes_on_bikes_allowed          (bikes_allowed)
#  index_current_routes_on_geometry               (geometry) USING gist
#  index_current_routes_on_onestop_id             (onestop_id) UNIQUE
#  index_current_routes_on_operator_id            (operator_id)
#  index_current_routes_on_tags                   (tags)
#  index_current_routes_on_updated_at             (updated_at)
#  index_current_routes_on_vehicle_type           (vehicle_type)
#  index_current_routes_on_wheelchair_accessible  (wheelchair_accessible)
#

class BaseRoute < ActiveRecord::Base
  self.abstract_class = true
  attr_accessor :serves, :does_not_serve, :operated_by

  extend Enumerize
  enumerize :vehicle_type,
            in: GTFS::Route::VEHICLE_TYPES.invert.inject({}) {
              |hash, (k,v)| hash[k.to_s.parameterize('_').to_sym] = v.to_s.to_i if k.present?; hash
            }
  enumerize :wheelchair_accessible, in: [:some_trips, :all_trips, :no_trips, :unknown]
  enumerize :bikes_allowed, in: [:some_trips, :all_trips, :no_trips, :unknown]

end

class Route < BaseRoute
  self.table_name_prefix = 'current_'

  include HasAOnestopId
  include HasAGeographicGeometry
  include HasTags
  include UpdatedSince
  include IsAnEntityImportedFromFeeds
  include IsAnEntityWithIssues

  include CanBeSerializedToCsv
  def self.csv_column_names
    [
      'ID Onestop',
      'Nome',
      'Operada por (nome)',
      'Operada por (ID Onestop)'
    ]
  end

  def csv_row_values
    [
      onestop_id,
      name,
      operator.try(:name),
      operator.try(:onestop_id)
    ]
  end

  include CurrentTrackedByChangeset
  current_tracked_by_changeset({
    kind_of_model_tracked: :onestop_entity,
    virtual_attributes: [
      :serves,
      :does_not_serve,
      :operated_by,
      :add_imported_from_feeds,
      :not_imported_from_feeds
    ],
    protected_attributes: [],
    sticky_attributes: [
      :name,
      :geometry,
      :color,
      :vehicle_type
    ]
  })

  def update_associations(changeset)
    update_entity_imported_from_feeds(changeset)
    if self.operated_by
      operator = Operator.find_by_onestop_id!(self.operated_by)
      self.update_columns(operator_id: operator.id)
    end
    OperatorRouteStopRelationship.manage_multiple(
      route: {
        serves: self.serves || [],
        does_not_serve: self.does_not_serve || [],
        model: self
      },
      changeset: changeset
    )
    super(changeset)
  end

  def before_destroy_making_history(changeset, old_model)
    routes_serving_stop.each do |route_serving_stop|
      route_serving_stop.destroy_making_history(changeset: changeset)
    end
    route_stop_patterns.each do |route_stop_pattern|
      route_stop_pattern.destroy_making_history(changeset: changeset)
    end
    return true
  end

  has_many :routes_serving_stop
  has_many :stops, through: :routes_serving_stop
  has_many :schedule_stop_pairs
  has_many :route_stop_patterns
  belongs_to :operator

  validates :name, presence: true
  validate :validate_color_attr

  def validate_color_attr
    errors.add(:color, "invalid color") unless Route.color_valid?(self.color)
  end

  def self.color_valid?(color)
    return true if color.to_s.empty?
    !!(/^[0-9A-F]{6}$/.match(color))
  end

  def self.color_from_gtfs(route_color)
    route_color.upcase if route_color && Route.color_valid?(route_color.upcase)
  end

  scope :where_serves, -> (onestop_ids_and_models) {
    # Accept one or more Stop models / onestop_ids.
    onestop_ids_and_models = Array.wrap(onestop_ids_and_models)
    stops, onestop_ids = onestop_ids_and_models.partition { |i| i.is_a?(Stop) }
    stops += Stop.find_by_onestop_ids!(onestop_ids)
    joins{routes_serving_stop.route}.where{routes_serving_stop.stop_id.in(stops.map(&:id))}.uniq
  }

  scope :operated_by, -> (models_or_onestop_ids) {
    models_or_onestop_ids = Array.wrap(models_or_onestop_ids)
    if models_or_onestop_ids.all? { |model_or_onestop_id| model_or_onestop_id.is_a?(Operator) }
      where(operator: models_or_onestop_ids)
    elsif models_or_onestop_ids.all? { |model_or_onestop_id| model_or_onestop_id.is_a?(String) }
      operators = Operator.find_by_onestop_ids!(models_or_onestop_ids)
      where(operator: operators)
    else
      raise ArgumentError.new('must provide Operator models or Onestop IDs')
    end
  }

  scope :traverses, -> (route_stop_pattern_onestop_id) {
    where(id: RouteStopPattern.select(:route_id).where(onestop_id: route_stop_pattern_onestop_id))
  }

  scope :stop_within_bbox, -> (bbox) {
    where(id: RouteServingStop.select(:route_id).where(stop: Stop.geometry_within_bbox(bbox)))
  }

  scope :where_vehicle_type, -> (vehicle_types) {
    # Titleize input: high_speed_rail_service -> High Speed Rail Service
    # Then convert back to GTFS spec vehicle_type integer.
    vehicle_types = Array.wrap(vehicle_types).map { |vt| GTFS::Route.match_vehicle_type(vt.to_s.titleize).to_s.to_i }
    where(vehicle_type: vehicle_types)
  }

  def self.representative_geometry(route, route_rsps)
    # build a hash of stop pair keys to a set of rsps that traverses them.
    stop_pairs_to_rsps = {}

    route_rsps.each do |rsp|
      rsp.stop_pattern.each_cons(2) do |s1, s2|
        if stop_pairs_to_rsps.has_key?([s1,s2])
          stop_pairs_to_rsps[[s1,s2]].add(rsp)
        else
          stop_pairs_to_rsps[[s1,s2]] = Set.new([rsp])
        end
      end
    end

    representative_rsps = Set.new

    # every stop pair is guaranteed to be represented by at least one rsp
    # caveat: if a stop pair has multiple geometries, a rare possibility,
    # those other geometries may not be represented.
    while (!stop_pairs_to_rsps.empty?)
      # choose and remove a random stop pair key
      key_value = stop_pairs_to_rsps.shift
      # be greedy and choose the rsp with the most stops
      rsp = key_value[1].max_by { |rsp|
        rsp.stop_pattern.uniq.size
      }
      representative_rsps.add(rsp)

      # remove the stop pair keys traversed by the chosen repr rsp
      stop_pairs_to_rsps.each_pair { |key_stop_pair, stop_pair_rsps|
        stop_pairs_to_rsps.delete(key_stop_pair) if stop_pair_rsps.include?(rsp)
      }
    end
    representative_rsps
  end

  def self.geometry_from_rsps(route, repr_rsps)
    # repr_rsps can be any enumerable subset of the route rsps
    route.geometry = Route::GEOFACTORY.multi_line_string(
      (repr_rsps || []).map { |rsp|
        factory = RGeo::Geos.factory
        line = factory.line_string(rsp.geometry[:coordinates].map { |lon, lat| factory.point(lon, lat) })
        # Using Douglas-Peucker
        Route::GEOFACTORY.line_string(
          line.simplify(0.00001).coordinates.map { |lon, lat| Route::GEOFACTORY.point(lon, lat) }
        )
      }
    )
  end

  ##### FromGTFS ####
  def generate_onestop_id
    stops = self.serves || self.stops
    fail Exception.new('no Stop coordinates') if stops.empty?
    fail Exception.new('name required') if name.nil?
    geohash = GeohashHelpers.fit(Stop::GEOFACTORY.collection(stops.map { |s| s.geometry_centroid }))
    onestop_id = OnestopId.handler_by_model(self.class).new(
      geohash: geohash,
      name: name
    )
    onestop_id.to_s
  end
end

class OldRoute < BaseRoute
  include OldTrackedByChangeset
  include HasAGeographicGeometry

  has_many :old_routes_serving_stop
  has_many :routes, through: :old_routes_serving_stop, source_type: 'Route'
end
