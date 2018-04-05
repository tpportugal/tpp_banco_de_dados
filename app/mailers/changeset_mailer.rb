class ChangesetMailer < ApplicationMailer
  def creation(changeset_id)
    @changeset = Changeset.find(changeset_id)
    mail to: @changeset.user.email,
         subject: "Olá do TPP. Recebemos a sua contribuição!"
  end

  def application(changeset_id)
    @changeset = Changeset.find(changeset_id)
    mail to: @changeset.user.email,
         subject: "Olá do TPP. Adicionámos a sua contribuição!"
  end
end
