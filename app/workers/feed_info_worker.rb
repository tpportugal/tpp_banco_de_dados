require 'net/http'

class FeedInfoWorker
  include Sidekiq::Worker
  sidekiq_options queue: :high,
                  retry: false

  def perform(url, cachekey)
    @url = url
    @cachekey = cachekey
    @progress_checkpoint = 0.0
    # Partials
    progress_download = lambda { |count,total| progress_check('buscando', count, total) }
    progress_graph = lambda { |count,total,entity| progress_check('analisando', count, total) }
    # Download & parse feed
    feed, operators = nil, []
    errors = []
    warnings = []
    begin
      # Pass in progress_download, progress_graph callbacks
      gtfs = GTFS::Source.build(
        @url,
        progress_download: progress_download,
        progress_graph: progress_graph,
        strict: false,
        auto_detect_root: true,
        tmpdir_basepath: Figaro.env.gtfs_tmpdir_basepath.presence
      )
      feed_info = FeedInfo.new(url: @url, gtfs: gtfs)
      feed, operators = feed_info.parse_feed_and_operators
    rescue GTFS::InvalidURLException => e
      errors << {
        exception: 'InvalidURLException',
        message: 'Ocorreu um erro ao buscar o ficheiro. Verifique o endereço e tente de novo, ou contacte o operador de transportes públicos para tentar resolver o problema.'
      }
    rescue GTFS::InvalidResponseException => e
      errors << {
        exception: 'InvalidResponseException',
        message: "There was an error downloading the file. The transit operator server responded with: #{e.to_s}.",
        message: "Ocorreu um erro ao buscar o ficheiro. O servidor do operador de transportes públicos responde com: #{e.to_s}.",
        response_code: e.response_code
      }
    rescue GTFS::InvalidZipException => e
      errors << {
        exception: 'InvalidZipException',
        message: 'O ficheiro zip parece estar corrompido.'
      }
    rescue GTFS::InvalidSourceException => e
      errors << {
        exception: 'InvalidSourceException',
        message: 'Este ficheiro não parece ser uma feed GTFS válida. Contacte o TPP para tentar resolver o problema.'
      }
    rescue StandardError => e
      errors << {
        exception: e.class.name,
        message: 'There was a problem downloading or processing from this URL.'
        message: 'Ocorreu um problema ao buscar ou processar deste URL.'
      }
    end

    if feed && feed.persisted?
      warnings << {
        onestop_id: feed.onestop_id,
        message: "Feed existente: #{feed.onestop_id}"
      }
    end
    operators.each do |operator|
      if operator && operator.persisted?
        warnings << {
          onestop_id: operator.onestop_id,
          message: "Operador existente: #{operator.onestop_id}"
        }
      end
    end

    response = {}
    if feed
      response[:feed] = FeedSerializer.new(feed).as_json
    end
    if operators
      response[:operators] = operators.map { |o| OperatorSerializer.new(o).as_json }
    end
    response[:status] = errors.size > 0 ? 'erro' : 'completo'
    response[:errors] = errors
    response[:warnings] = warnings
    response[:url] = url
    Rails.cache.write(cachekey, response, expires_in: FeedInfo::CACHE_EXPIRATION)
    response
  end

  private

  def progress_check(status, count, total)
    # Update upgress if more than 10% work done since last update
    return if total.to_f == 0
    current = count / total.to_f
    if (current - @progress_checkpoint) >= 0.05
      progress_update(status, current)
    end
  end

  def progress_update(status, current)
    # Write progress to cache
    current = 1.0 if current > 1.0
    @progress_checkpoint = current
    cachedata = {
      status: status,
      url: @url,
      progress: current
    }
    Rails.cache.write(@cachekey, cachedata, expires_in: FeedInfo::CACHE_EXPIRATION)
  end
end
