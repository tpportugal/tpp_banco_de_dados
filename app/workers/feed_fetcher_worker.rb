class FeedFetcherWorker
  include Sidekiq::Worker
  sidekiq_options queue: :default,
                  retry: false,
                  unique: :until_and_while_executing,
                  unique_job_expiration: 22 * 60 * 60, # 22 hours
                  log_duplicate_payload: true

  def perform(feed_onestop_id)
    begin
      feed = Feed.find_by_onestop_id!(feed_onestop_id)
      log "FeedFetcherWorker verificando #{feed.onestop_id}"
      feed_version = FeedFetcherService.fetch_and_return_feed_version(feed)
      if feed_version
        log "FeedFetcherWorker verificou #{feed.onestop_id} e encontrou a sha1: #{feed_version.sha1}"
      else
        log "FeedFetcherWorker verificou #{feed.onestop_id} e não retornou nenhuma FeedVersion"
      end
    rescue Exception => e
      # NOTE: we're catching all exceptions, including Interrupt,
      #   SignalException, and SyntaxError
      log e.message, :error
      log e.backtrace, :error
      if defined?(Raven)
        Raven.capture_exception(e, {
          tags: {
            'feed_onestop_id' => feed_onestop_id
          }
        })
      end
    end
  end
end
