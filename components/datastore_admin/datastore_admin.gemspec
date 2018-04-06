$:.push File.expand_path('../lib', __FILE__)

# Maintain your gem's version:
require 'datastore_admin/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'datastore_admin'
  s.version     = DatastoreAdmin::VERSION
  s.authors     = ['Rui J Santos']
  s.email       = ['rui.s@gmx.pt']
  s.homepage    = 'https://github.com/tpportugal/tpp_banco_de_dados'
  s.summary     = 'Admin interface for the TPP Datastore.'
  s.description = 'Admin interface for the TPP Datastore, wrapped as a Rails engine.
                   Keeps HTML-generating views out of the core of the Datastore, which is
                   focused on serving a JSON API.'
  s.license     = 'MIT'

  s.files = Dir['{app,config,db,lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.rdoc']

  s.add_dependency 'sinatra' # for Sidekiq dashboard
end
