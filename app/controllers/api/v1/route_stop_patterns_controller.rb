class Api::V1::RouteStopPatternsController < Api::V1::CurrentEntityController
  def self.model
    RouteStopPattern
  end

  private

  def index_query
    super
    if params[:traversed_by].present?
      @collection = @collection.where(route: Route.find_by_onestop_id!(params[:traversed_by]))
    end
    if params[:trips].present?
      @collection = @collection.with_trips(AllowFiltering.param_as_array(params, :trips))
    end
    if params[:stops_visited].present?
      @collection = @collection.with_all_stops(params[:stops_visited])
    end
  end

  def index_includes
    super
    @collection = @collection.includes{[
      route,
    ]}
  end

  def query_params
    super.merge({
      traversed_by: {
        desc: "Atravessado pelo PadrãoRotaParagem",
        type: "onestop_id"
      },
      trips: {
        desc: "Importado da viagem com o ID no GTFS",
        type: "string",
        array: true
      },
      stops_visited: {
        desc: "Visita a Paragem",
        type: "onestop_id"
      }
    })
  end
end
