class Api::V1::FeedsController < Api::V1::BaseApiController
  include JsonCollectionPagination
  include DownloadableCsv
  include AllowFiltering
  include Geojson

  before_action :set_feed, only: [:show]

  def index
    @feeds = Feed.where('').includes{[
      operators_in_feed,
      operators_in_feed.operator,
      changesets_imported_from_this_feed,
      active_feed_version,
      feed_versions
    ]}

    @feeds = AllowFiltering.by_onestop_id(@feeds, params)
    @feeds = AllowFiltering.by_tag_keys_and_values(@feeds, params)
    @feeds = AllowFiltering.by_attribute_since(@feeds, params, :last_imported_since, :last_imported_at)

    if params[:latest_fetch_exception].present?
      @feeds = @feeds.where_latest_fetch_exception(AllowFiltering.to_boolean(params[:latest_fetch_exception]))
    end

    if params[:bbox].present?
      @feeds = @feeds.geometry_within_bbox(params[:bbox])
    end

    if params[:active_feed_version_valid].present?
      @feeds = @feeds.where_active_feed_version_valid(params[:active_feed_version_valid])
    end

    if params[:active_feed_version_expired].present?
      @feeds = @feeds.where_active_feed_version_expired(params[:active_feed_version_expired])
    end

    if params[:active_feed_version_update].presence == 'true'
      @feeds = @feeds.where_active_feed_version_update
    end

    if params[:active_feed_version_import_level].present?
      @feeds = @feeds.where_active_feed_version_import_level(params[:active_feed_version_import_level])
    end

    if params[:latest_feed_version_import_status].present?
      @feeds = @feeds.where_latest_feed_version_import_status(AllowFiltering.to_boolean(params[:latest_feed_version_import_status]))
    end

    respond_to do |format|
      format.json { render paginated_json_collection(@feeds) }
      format.geojson { render paginated_geojson_collection(@feeds) }
      format.csv { return_downloadable_csv(@feeds, 'feeds') }
    end
  end

  def show
    respond_to do |format|
      format.json { render json: @feed }
      format.geojson { render json: @feed, serializer: GeoJSONSerializer }
    end
  end

  def fetch_info
    url = params[:url]
    raise Exception.new('invalid URL') if url.empty?
    # Use read/write instead of fetch block to avoid race with Sidekiq.
    cachekey = "feeds/fetch_info/#{url}"
    cachedata = Rails.cache.read(cachekey)
    if !cachedata
      cachedata = {status: 'queued', url: url}
      Rails.cache.write(cachekey, cachedata, expires_in: FeedInfo::CACHE_EXPIRATION)
      FeedInfoWorker.perform_async(url, cachekey)
    end
    if cachedata[:status] == 'error'
      render json: cachedata, status: 500
    else
      render json: cachedata
    end
  end

  private

  def query_params
    params.slice(
      :tag_key,
      :tag_value,
      :bbox,
      :last_imported_since,
      :active_feed_version_valid,
      :active_feed_version_expired,
      :active_feed_version_update,
      :active_feed_version_import_level,
      :latest_feed_version_import_status,
      :latest_fetch_exception
    )
  end

  def set_feed
    @feed = Feed.find_by_onestop_id!(params[:id])
  end

  def sort_reorder(collection)
    if sort_key == 'latest_feed_version_import.created_at'.to_sym
      collection = collection.with_latest_feed_version_import
      collection.reorder("latest_feed_version_import.created_at #{sort_order}")
    else
      super
    end
  end
end
