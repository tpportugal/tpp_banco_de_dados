class Api::V1::CurrentEntityController < Api::V1::BaseApiController
  include JsonCollectionPagination
  include DownloadableCsv
  include AllowFiltering

  def self.model
    fail Exception.new("Método Abstrato")
  end

  def index
    index_query
    index_includes
    respond_to do |format|
      format.json { render paginated_json_collection(@collection).merge({ scope: render_scope, each_serializer: render_serializer }) }
      format.geojson { render paginated_geojson_collection(@collection).merge({ scope: render_scope }) }
      format.csv { return_downloadable_csv(@collection, self.class.model.name.underscore.pluralize) }
    end
  end

  def show
    set_model
    respond_to do |format|
      format.json { render json: @model, serializer: render_serializer, scope: render_scope }
      format.geojson { render json: @model, serializer: GeoJSONSerializer }
    end
  end

  private

  def index_query
    # Entity
    @collection = (self.class.model).where('')
    @collection = AllowFiltering.by_onestop_id(@collection, params)
    @collection = AllowFiltering.by_tag_keys_and_values(@collection, params)
    @collection = AllowFiltering.by_updated_since(@collection, params)

    # Geometry
    index_query_geometry

    # Imported From Feed
    if params[:imported_from_feed].present?
      @collection = @collection.where_imported_from_feed(Feed.find_by_onestop_id!(params[:imported_from_feed]))
    end
    if params[:imported_from_feed_version].present?
      @collection = @collection.where_imported_from_feed_version(FeedVersion.find_by!(sha1: params[:imported_from_feed_version]))
    end
    if params[:imported_from_active_feed_version].presence.eql?("true")
      @collection = @collection.where_imported_from_active_feed_version
    end
    if params[:imported_with_gtfs_id].present?
      @collection = @collection.where_imported_with_gtfs_id(params[:gtfs_id] || params[:imported_with_gtfs_id])
    end
    if params[:import_level].present?
      @collection = @collection.where_import_level(AllowFiltering.param_as_array(params, :import_level))
    end
  end

  def index_query_geometry
    if [params[:lat], params[:lon]].map(&:present?).all?
      point = (self.class.model)::GEOFACTORY.point(params[:lon], params[:lat])
      r = params[:r] || 100 # meters TODO: move this to a more logical place
      @collection = @collection.where{st_dwithin(geometry, point, r)}.order{st_distance(geometry, point)}
    end
    if params[:bbox].present?
      @collection = @collection.geometry_within_bbox(params[:bbox])
    end
  end

  def index_includes
    scope = render_scope
    @collection = @collection.includes{[imported_from_feeds, imported_from_feed_versions]} if scope[:imported_from_Feeds]
    @collection = @collection.includes(:issues) if scope[:issues]
  end

  def render_scope
    # Get the list of include and exclude options
    incl = {
      geometry: true,
      issues: false,
      imported_from_feeds: false,
      id: false
    }
    AllowFiltering.param_as_array(params, :include).map(&:to_sym).each { |i| incl[i] = true }
    AllowFiltering.param_as_array(params, :exclude).map(&:to_sym).each { |i| incl[i] = false }
    # Backwards compat
    ii = AllowFiltering.to_boolean(params[:embed_issues])
    incl[:issues] = ii if !ii.nil?
    eg = AllowFiltering.to_boolean(params[:exclude_geometry])
    ig = AllowFiltering.to_boolean(params[:include_geometry])
    incl[:geometry] = true if (ig == true || eg == false)
    incl[:geometry] = false if (ig == false || eg == true)
    return incl
  end

  def render_serializer
    ActiveModel::Serializer.serializer_for(self.class.model)
  end

  def set_model
    @model = (self.class.model).find_by_onestop_id!(params[:id])
  end

  def query_params
    # Allowed query parameters - and documentation
    super.merge({
      onestop_id: {
        desc: "ID Onestop",
        type: "onestop_id",
        array: true
      },
      lat: {
        desc: "Latitude",
        type: "float"
      },
      lon: {
        desc: "Longitude",
        type: "float"
      },
      r: {
        desc: "Raio, em metros",
        type: "float"
      },
      bbox: {
        desc: "Caixa delimitadora",
        type: "bbox"
      },
      updated_since: {
        desc: "Atualizada desde",
        type: "datetime"
      },
      import_level: {
        desc: "Nível de Importação",
        type: "integer",
        array: true
      },
      imported_with_gtfs_id: {
        desc: "Importada com o ID GTFS",
        type: "string",
        array: true
      },
      gtfs_id: {
        show: false
      },
      imported_from_feed: {
        desc: "Importada da Feed",
        type: "onestop_id",
        array: true
      },
      imported_from_feed_version: {
        desc: "Importada da Versão de Feed",
        type: "sha1",
        array: true
      },
      imported_from_active_feed_version: {
        desc: "Importada da Versão de Feed atualmente ativa",
        type: "boolean"
      },
      tag_key: {
        desc: "Chave da Tag",
        type: "string"
      },
      tag_value: {
        desc: "Valor da Tag",
        type: "string"
      },
      include: {
        desc: "Incluir valores",
        type: "enum",
        enum: ["geometry","imported_from_feeds","issues"]
      },
      exclude: {
        desc: "Excluir valores",
        type: "enum",
        enum: ["geometry","imported_from_feeds","issues"]
      },
      embed_issues: {
        desc: "Embutir Problemas",
        type: "boolean",
        show: false
      },
      include_geometry: {
        desc: "Incluir geometria",
        type: "boolean",
        show: false
      },
      exclude_geometry: {
        desc: "Excluir geometria",
        type: "boolean",
        show: false
      }
    })
  end
end
