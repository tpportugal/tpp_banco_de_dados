#encoding: UTF-8

xml.instruct! :xml, :version => "1.0"
xml.rss :version => "2.0" do
  xml.channel do
    xml.title "Feed de Atividades do Banco de Dados TPP"
    xml.author "TPP"
    xml.description "Importação, alterações, e atualizações de dados abertos de transportes públicos no Banco de Dados TPP e no processo de importação do FeedEater"
    xml.link url_for(controller: :activity_updates, action: :index, only_path: false)
    xml.language "pt"

    @activity_updates.each do |update|
      xml.item do
        xml.title "#{update[:entity_type]} #{update[:entity_action]}"
        if update[:by_user_id]
          # TODO: list user name or e-mail?
          xml.author update[:by_user_id]
        end
        xml.pubDate update[:at_datetime] #.to_s(:rfc822)
        xml.link url_for(
          controller: update[:entity_type].pluralize,
          action: :show,
          id: update[:entity_id],
          only_path: false
        )
        # xml.guid article.id
        if update[:note]
          xml.description "<p>" + update[:note] + "</p>"
        end
      end
    end
  end
end
