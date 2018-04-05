class Api::V1::StopsController < Api::V1::CurrentEntityController
  def self.model
    Stop
  end

  private

  def index_query
    super
    if params[:served_by].present? || params[:servedBy].present?
      # we previously allowed `servedBy`, so we'll continue to honor that for the time being
      operator_onestop_ids = []
      operator_onestop_ids += params[:served_by].split(',') if params[:served_by].present?
      operator_onestop_ids += params[:servedBy].split(',') if params[:servedBy].present?
      operator_onestop_ids.uniq!
      @collection = @collection.served_by(operator_onestop_ids)
    end
    if params[:served_by_vehicle_types].present?
      @collection = @collection.served_by_vehicle_types(AllowFiltering.param_as_array(params, :served_by_vehicle_types))
    end
    if params[:wheelchair_boarding].present?
      @collection = @collection.where(wheelchair_boarding: AllowFiltering.to_boolean(params[:wheelchair_boarding] ))
    end
  end

  def index_includes
    super
    @collection = @collection.includes{[
      operators_serving_stop,
      operators_serving_stop.operator,
      routes_serving_stop,
      routes_serving_stop.route,
      routes_serving_stop.route.operator
    ]}
  end

  def paginated_json_collection(collection)
    result = super
    result[:root] = :stops
    result[:each_serializer] = StopSerializer
    result
  end

  def query_params
    super.merge({
      served_by: {
        desc: "Servida pela Rota ou Operador",
        type: "onestop_id",
        array: true
      },
      servedBy: {
        show: false
      },
      served_by_vehicle_types: {
        desc: "Servida por veículos do tipo",
        type: "string",
        array: true
      },
      wheelchair_boarding: {
        desc: "Acessível a cadeiras de rodas",
        type: "boolean"
      }
    })
  end
end
