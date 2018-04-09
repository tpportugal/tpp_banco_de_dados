class Api::V1::RoutesController < Api::V1::CurrentEntityController
  def self.model
    Route
  end

  private

  def index_query
    super
    if params[:serves].present?
      @collection = @collection.where_serves(AllowFiltering.param_as_array(params, :serves))
    end
    if params[:operated_by].present? || params[:operatedBy].present?
      # we previously allowed `operatedBy`, so we'll continue to honor that for the time being
      param = params[:operated_by].present? ? :operated_by : :operatedBy
      operator_onestop_ids = AllowFiltering.param_as_array(params, param)
      @collection = @collection.operated_by(operator_onestop_ids)
    end
    if params[:traverses].present?
      @collection = @collection.traverses(params[:traverses].split(','))
    end
    if params[:vehicle_type].present?
      # some could be integers, some could be strings
      @collection = @collection.where_vehicle_type(AllowFiltering.param_as_array(params, :vehicle_type))
    end
    if params[:color].present?
      if ['true', true].include?(params[:color])
        @collection = @collection.where.not(color: nil)
      else
        @collection = @collection.where(color: params[:color].upcase)
      end
    end
    if params[:wheelchair_accessible].present?
      @collection = @collection.where(wheelchair_accessible: params[:wheelchair_accessible])
    end
    if params[:bikes_allowed].present?
      @collection = @collection.where(bikes_allowed: params[:bikes_allowed])
    end
  end

  def query_includes
    super
    @collection = @collection.includes{[
      operator,
      stops,
      route_stop_patterns
    ]}
  end

  def index_query_geometry
    if [params[:lat], params[:lon]].map(&:present?).all?
      point = (self.class::MODEL)::GEOFACTORY.point(params[:lon], params[:lat])
      r = params[:r] || 100 # meters TODO: move this to a more logical place
      @collection = @collection.where{st_dwithin(geometry, point, r)}.order{st_distance(geometry, point)}
    end
    if params[:bbox].present?
      @collection = @collection.stop_within_bbox(params[:bbox])
    end
  end

  def query_params
    super.merge({
      operated_by: {
        desc: "Operador",
        type: "onestop_id",
        array: true
      },
      operatedBy: {
        show: false
      },
      serves: {
        desc: "Serve a Paragem",
        type: "onestop_id",
        array: true
      },
      traverses: {
        desc: "Atravessa o PadrãoRotaParagem",
        type: "onestop_id",
        array: true
      },
      color: {
        desc: "Cor da Rota",
        type: "string"
      },
      vehicle_type: {
        desc: "Tipo de Veículo",
        format: "string",
        array: true
      },
      wheelchair_accessible: {
        desc: "Acessível a cadeiras de rodas",
        format: "boolean",
        array: true
      },
      bikes_allowed: {
        desc: "Bicicletas permitidas",
        format: "boolean"
      }
    })
  end
end
