if Rails.env.staging? || Rails.env.production?
  CarrierWave.configure do |config|
    config.fog_provider    = 'file'
    config.fog_directory  = 'uploads'
    config.fog_public     = false
    config.fog_attributes = { 'Cache-Control' => "max-age=#{365.day.to_i}" }
  end
end
