unless Rails.env.test?
  Figaro.require_keys("TPP_DATASTORE_AUTH_TOKEN")
end
