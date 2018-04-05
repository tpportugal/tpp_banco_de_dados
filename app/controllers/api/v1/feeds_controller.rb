class Api::V1::FeedsController < Api::V1::CurrentEntityController
  def self.model
    Feed
  end

  def fetch_info
    url = params[:url]
    raise Exception.new('URL inválido') if url.empty?
    # Use read/write instead of fetch block to avoid race with Sidekiq.
    cachekey = "feeds/fetch_info/#{url}"
    cachedata = Rails.cache.read(cachekey)
    if !cachedata
      cachedata = {status: 'agendado', url: url}
      Rails.cache.write(cachekey, cachedata, expires_in: FeedInfo::CACHE_EXPIRATION)
      FeedInfoWorker.perform_async(url, cachekey)
    end
    if cachedata[:status] == 'erro'
      render json: cachedata, status: 500
    else
      render json: cachedata
    end
  end

  def download_latest_feed_version
    set_model
    feed_version = @model.feed_versions.order(fetched_at: :desc).first!
    if feed_version.download_url.present?
      redirect_to feed_version.download_url, status: 302
    else
      fail ActiveRecord::RecordNotFound, "Não está disponível nenhuma versão da feed ou a sua licença não permite redistribuição"
    end
  end

  def feed_version_update_statistics
    set_model
    render json: Feed.feed_version_update_statistics(@model)
  end

  private

  def index_query
    super
    @collection = AllowFiltering.by_attribute_array(@collection, params, :name)
    @collection = AllowFiltering.by_attribute_array(@collection, params, :url, case_sensitive: true)
    @collection = AllowFiltering.by_attribute_since(@collection, params, :last_imported_since, :last_imported_at)
    if params[:latest_fetch_exception].present?
      @collection = @collection.where_latest_fetch_exception(AllowFiltering.to_boolean(params[:latest_fetch_exception]))
    end
    if params[:active_feed_version_valid].present?
      @collection = @collection.where_active_feed_version_valid(params[:active_feed_version_valid])
    end
    if params[:active_feed_version_expired].present?
      @collection = @collection.where_active_feed_version_expired(params[:active_feed_version_expired])
    end
    if params[:active_feed_version_update].presence == 'true'
      @collection = @collection.where_active_feed_version_update
    end
    if params[:active_feed_version_import_level].present?
      @collection = @collection.where_active_feed_version_import_level(params[:active_feed_version_import_level])
    end
    if params[:latest_feed_version_import_status].present?
      @collection = @collection.where_latest_feed_version_import_status(AllowFiltering.to_boolean(params[:latest_feed_version_import_status]))
    end
  end

  def index_includes
    super
    @collection = @collection.includes{[
      changesets_imported_from_this_feed,
      operators_in_feed,
      operators_in_feed.operator,
      active_feed_version
    ]}
  end

  def query_params
    super.merge({
      name: {
        desc: "Nome da feed",
        type: "string",
        array: true
      },
      last_imported_since: {
        desc: "Última importação desde",
        type: "datetime"
      },
      latest_fetch_exception: {
        desc: "A ultima busca produziu uma exceçaõ",
        type: "boolean"
      },
      active_feed_version_valid: {
        desc: "A Versão de Feed ativa está válida nesta data",
        type: "datetime"
      },
      active_feed_version_expired: {
        desc: "A Versão de Feed ativa está expirada nesta data",
        type: "datetime"
      },
      active_feed_version_update: {
        desc: "Existe uma Versão de Feed mais recente que a Versão de Feed atualmente ativa",
        type: "boolean"
      },
      active_feed_version_import_level: {
        desc: "Nível de Importação da Versão de Feed ativa",
        type: "integer"
      },
      latest_feed_version_import_status: {
        desc: "Estado da importação mais recente",
        type: "string"
      },
      url: {
        desc: "URL",
        type: "string",
        array: true
      }
    })
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
