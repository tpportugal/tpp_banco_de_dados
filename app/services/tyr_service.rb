# This Ruby script queries the Tyr ("take your route") service
# to associate a latitude-longitude pair with the closest OSM way.

require 'singleton'

class TyrService
  include Singleton

  BASE_URL = Figaro.env.tyr_host || 'https://routing.tpp.pt'
  MAX_LOCATIONS_PER_REQUEST = 100

  class Error < StandardError
  end

  def self.locate(locations: [], costing: 'transit')
    response = connection.get('/locate') do |req|
      json_payload = {
        locations: locations,
        costing: costing
      }
      req.params['json'] = JSON.dump(json_payload)
      req.params['api_key'] = Figaro.env.tyr_auth_token
    end

    if response.body.blank?
      raise Error.new('O Tyr retornou uma resposta vazia')
    elsif [401, 403].include?(response.status)
      raise Error.new('O pedido ao Tyr não foi autorizado. A TYR_AUTH_TOKEN está definida?')
    elsif response.status == 504
      raise Error.new('O pedido ao Tyr esgotou o tempo limite. Tem a certeza que o Tyr está acessível?')
    elsif response.status == 200
      raw_json = response.body
      parsed_json = JSON.parse(raw_json)
      parsed_json.map(&:deep_symbolize_keys)
    else
      raise Error.new("O Tyr retornou um erro inesperado\n#{response.body}")
    end
  end

  private

  def self.connection
    @conn ||= Faraday.new(url: BASE_URL) do |faraday|
      faraday.request  :url_encoded             # form-encode POST params
      faraday.response :logger                  # log requests to STDOUT
      faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
    end
    @conn
  end
end
