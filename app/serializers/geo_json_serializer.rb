class GeoJSONSerializer < ApplicationSerializer
  attributes :geometry,
             :properties,
             :type,
             :id

  def properties
    ActiveModel::Serializer
      .serializer_for(object)
      .new(object)
      .as_json
      .except(:geometry)
      .merge({title: object.try(:onestop_id)})
  end

  def type
    'Feature'
  end

  def id
    object.try(:onestop_id)
  end

  def geometry
    object.try(:geometry)
  end

end
