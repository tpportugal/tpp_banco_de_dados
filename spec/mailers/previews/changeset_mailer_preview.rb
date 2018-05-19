# Preview all emails at http://localhost:8004/rails/mailers/changeset_mailer

class ChangesetMailerPreview < ActionMailer::Preview
  def creation
    changeset = Changeset.where.not(user: nil).take
    ChangesetMailer.creation(changeset) if changeset
  end

  def application
    changeset = Changeset.where.not(user: nil).take
    ChangesetMailer.application(changeset) if changeset
  end
end
