# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ActionController::MimeResponds

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from Moab::ObjectNotFoundException, with: :not_found
  rescue_from InvalidSuriSyntax, with: :bad_request

  protected

  def strip_druid(id)
    id&.split(':', 2)&.last
  end

  def bad_request
    render plain: '400 bad request', status: :bad_request
  end

  def not_found
    render plain: '404 Not Found', status: :not_found
  end

  # TODO: get rid of this once https://github.com/sul-dlss/moab-versioning/issues/159 is implemented
  def refine_invalid_druid_error!(err)
    # make a specific moab-versioning StandardError into something more easily manageable by ApplicationController...
    raise InvalidSuriSyntax, err.message if err.message.include?('Identifier has invalid suri syntax')
    raise # ...but just re-raise what we got if it was something else
  end
end
