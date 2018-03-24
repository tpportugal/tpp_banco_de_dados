class ApplicationMailer < ActionMailer::Base
  default from: "api@tpp.pt" # TODO: change to a real email address
  layout 'mailer'
end
