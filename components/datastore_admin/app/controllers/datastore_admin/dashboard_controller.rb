module DatastoreAdmin
  class DashboardController < ApplicationController
    def main

    end

    def dispatcher
      if Rails.env.development?
        @iframe_url = 'http://localhost:4200'
      else
        @iframe_url = '/expedidor'
      end
      render :iframed_dashboard
    end

    def sidekiq_dashboard
      @iframe_url = 'sidekiq'
      render :iframed_dashboard
    end

    def postgres_dashboard
      @iframe_url = 'postgres'
      render :iframed_dashboard
    end

    def reset
      begin
        ResetDatastore.clear_enqueued_jobs if params[:clear_enqueued_jobs]
        ResetDatastore.destroy_feed_versions if params[:destroy_feed_versions]
        ResetDatastore.truncate_database if params[:truncate_database]
      rescue
        flash[:error] = $!.message
      else
        messages = []
        messages << 'Tarefas agendadas limpas com sucesso.' if params[:clear_enqueued_jobs]
        messages << 'Versões de feed destruídas com sucesso.' if params[:destroy_feed_versions]
        messages << 'Base de dados truncada com sucesso.' if params[:truncate_database]
        if messages.size > 0
          flash[:success] = messages.join(' ')
        else
          flash[:info] = "Não marcou nenhuma opção, então não fiz nada."
        end

        workers = Sidekiq::Workers.new
        if workers.size > 0
          flash[:warning] = "#{workers.size} tarefa(s) a ser(em) executada(s). Pode querer truncar a base de dados novamente quando as tarefas terminarem."
        end
      end

      redirect_to :root
    end
  end
end
