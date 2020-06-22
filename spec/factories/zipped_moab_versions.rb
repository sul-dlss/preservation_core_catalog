# frozen_string_literal: true

FactoryBot.define do
  # Because ZMVs are auto-created in callback, you probably don't create from this factory directly.
  # Instead create a :complete_moab and get the zipped_moab_versions from it
  factory :zipped_moab_version do
    version { 1 }
    zip_endpoint
    preserved_object
  end
end
