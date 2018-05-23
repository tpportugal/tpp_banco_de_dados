class ChangesetMailer < ApplicationMailer
  def creation(changeset_id)
    @changeset = Changeset.find(changeset_id)
    mail to: @changeset.user.email,
         subject: "Recebemos a sua contribuição ao TPP!"
  end

  def application(changeset_id)
    @changeset = Changeset.find(changeset_id)
    mail to: @changeset.user.email,
         subject: "Adicionámos a sua contribuição ao TPP!"
  end
end
