# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ObjectsController, type: :request do
  let(:prefixed_druid) { 'druid:bj102hs9687' }
  let(:bare_druid) { 'bj102hs9687' }
  let(:logger_double) { instance_double(Logger, info: nil, error: nil, add: nil) }

  before do
    allow(Audit::MoabToCatalog).to receive(:logger).and_return(logger_double)
    Audit::MoabToCatalog.check_existence_for_druid(bare_druid)
  end

  describe 'GET #file' do
    context 'when object exists' do
      context 'when druid is prefixed' do
        it 'returns the requested file' do
          get file_object_url(id: prefixed_druid), params: { category: 'manifest', filepath: 'manifestInventory.xml' }, headers: valid_auth_header
          expect(response).to have_http_status(:ok)
          expect(response.body).to include 'md5'
        end
      end

      context 'when druid is bare' do
        it 'returns the requested file' do
          get file_object_url(id: bare_druid), params: { category: 'manifest', filepath: 'manifestInventory.xml' }, headers: valid_auth_header
          expect(response).to have_http_status(:ok)
          expect(response.body).to include 'md5'
        end
      end

      context 'when file is not present in Moab' do
        it 'returns 404 response code; body has additional information' do
          get file_object_url(id: prefixed_druid), params: { category: 'manifest', filepath: 'foobar' }, headers: valid_auth_header
          expect(response).to have_http_status(:not_found)
          expect(response.body).to eq '404 Not Found: manifest file foobar not found for bj102hs9687 - 3'
        end
      end

      context 'when version specified' do
        it 'retrieves the correct version of the file' do
          params = { category: 'manifest', filepath: 'manifestInventory.xml', version: '3' }
          get file_object_url(id: prefixed_druid), params: params, headers: valid_auth_header
          expect(response).to have_http_status(:ok)
          expect(response.body).to include 'size="7133"'
        end

        context 'when version is too high' do
          it 'returns 404 response code with details' do
            get file_object_url(id: prefixed_druid), params: { category: 'manifest', filepath: 'ignored', version: '666' }, headers: valid_auth_header
            expect(response).to have_http_status(:not_found)
            expect(response.body).to eq '404 Not Found: Version ID 666 does not exist'
          end
        end

        context 'when version param is not digits only' do
          it 'returns 400 response code with details' do
            params = { category: 'manifest', filepath: 'manifestInventory.xml', version: 'v3' }
            get file_object_url(id: prefixed_druid), params: params, headers: valid_auth_header
            expect(response).to have_http_status(:bad_request)
            expect(response.body).to eq '400 Bad Request: version parameter must be positive integer'
          end
        end
      end

      context 'when ArgumentError from MoabStorageService' do
        it 'returns 400 response code with details' do
          get file_object_url(id: prefixed_druid), params: { category: 'metadata' }, headers: valid_auth_header
          expect(response).to have_http_status(:bad_request)
          error_response = JSON.parse(response.body)['errors'].first
          expect(error_response['detail']).to include('missing required parameters: filepath')
        end
      end
    end

    context 'when object does not exist' do
      it 'returns 404 response code with "No storage object found"' do
        get file_object_url(id: 'druid:xx123yy9999'), params: { category: 'manifest', filepath: 'manifestInventory.xml' }, headers: valid_auth_header
        expect(response).to have_http_status(:not_found)
        expect(response.body).to eq "404 Not Found: Couldn't find CompleteMoab with [WHERE \"preserved_objects\".\"druid\" = $1]"
      end
    end

    context 'when no id param' do
      context 'when id param is empty' do
        it 'returns 404 error' do
          get file_object_url(id: ''), params: { category: 'manifest', filepath: 'manifestInventory.xml' }, headers: valid_auth_header
          expect(response).to have_http_status(:not_found)
          error_response = JSON.parse(response.body)['errors'].first
          expect(error_response['detail']).to include("That request method and path combination isn't defined.")
        end
      end

      context 'when id param missing' do
        it 'Rails will raise error and do the right thing' do
          expect do
            get file_object_url({}), params: { category: 'manifest', filepath: 'manifestInventory.xml' }, headers: valid_auth_header
          end.to raise_error(ActionController::UrlGenerationError)
        end
      end
    end

    context 'when druid invalid' do
      it 'returns 400 error' do
        get file_object_url(id: 'foobar'), params: { category: 'manifest', filepath: 'manifestInventory.xml' }, headers: valid_auth_header
        expect(response).to have_http_status(:bad_request)
        error_response = JSON.parse(response.body)['errors'].first
        expect(error_response['detail']).to include('does not match value: "foobar", example: druid:bc123df4567')
      end
    end
  end
end
