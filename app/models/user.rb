# == Schema Information
#
# Table name: users
#
#  id                     :integer          not null, primary key
#  email                  :string           not null
#  name                   :string
#  affiliation            :string
#  user_type              :string
#  encrypted_password     :string           default(""), not null
#  reset_password_token   :string
#  reset_password_sent_at :datetime
#  sign_in_count          :integer          default(0), not null
#  current_sign_in_at     :datetime
#  last_sign_in_at        :datetime
#  current_sign_in_ip     :string
#  last_sign_in_ip        :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  admin                  :boolean          default(FALSE)
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#

class User < ActiveRecord::Base
  devise :database_authenticatable

  has_many :changesets

  validates :email, presence: true, uniqueness: true, email: true

  extend Enumerize
  enumerize :user_type, in: [
    :construtor_de_comunidades,
    :entusiasta_de_dados,
    :programador_de_aplicações,
    :fabricante_de_hardware,
    :consultor,
    :funcionário_de_operador_de_transportes,
    :funcionário_de_agência_pública
  ]

  include CanBeSerializedToCsv
  def self.csv_column_names
    [
      'Nome',
      'Afiliação',
      'Tipo de Utilizador',
      'Email'
    ]
  end
  def csv_row_values
    [
      name,
      affiliation,
      user_type,
      email
    ]
  end

  def admin?
    self.admin
  end
end
