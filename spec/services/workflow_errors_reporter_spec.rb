require 'rails_helper'

RSpec.describe WorkflowErrorsReporter do
  let(:full_url) do
    'https://sul-lyberservices-test.stanford.edu/workflow/dor/objects/druid:jj925bx9565/workflows/preservationAuditWF/moab-valid'
  end
  let(:headers) { { 'Content-Type' => 'application/xml' } }
  let(:result) { "Invalid moab, validation error...ential version directories." }
  let(:body) { "<process name='moab-valid' status='error' errorMessage='#{result}'/>" }
  let(:druid) { 'jj925bx9565' }
  let(:process_name) { 'moab-valid' }

  context '.update_workflow' do
    it '204 response' do
      allow(Settings).to receive(:workflow_services_url).and_return('https://sul-lyberservices-test.stanford.edu/workflow/')
      stub_request(:put, full_url)
        .with(body: body, headers: headers)
        .to_return(status: 204, body: "", headers: {})
      expect(Rails.logger).to receive(:debug).with("#{druid} - sent error to workflow service for preservationAuditWF moab-valid")
      described_class.update_workflow(druid, process_name, result)
    end

    it '400 response' do
      allow(Settings).to receive(:workflow_services_url).and_return('https://sul-lyberservices-test.stanford.edu/workflow/')
      stub_request(:put, full_url)
        .with(body: body, headers: headers)
        .to_return(status: 400, body: "", headers: {})
      expect(Rails.logger).to receive(:error).with("#{druid} - unable to update workflow for preservationAuditWF moab-valid #<Faraday::ClientError response={:status=>400, :headers=>{}, :body=>\"\"}>. Error message: Invalid moab, validation error...ential version directories.")
      described_class.update_workflow(druid, process_name, result)
    end

    it 'has invalid workflow_services_url' do
      stub_request(:put, full_url)
        .with(body: body, headers: headers)
        .to_return(status: 400, body: "", headers: {})
      expect(Rails.logger).to receive(:warn).with('no workflow hookup - assume you are in test or dev environment')
      described_class.update_workflow(druid, process_name, result)
    end
  end

  context '.request_params' do
    let(:headers_hash) { {} }
    let(:mock_request) { instance_double(Faraday::Request, headers: headers_hash) }

    it 'make sure request gets correct params' do
      error_msg = "Invalid moab, validation error...ential version directories."
      expect(mock_request).to receive(:url).with("/workflow/dor/objects/druid:#{druid}/workflows/preservationAuditWF/#{process_name}")
      expect(mock_request).to receive(:body=).with("<process name='#{process_name}' status='error' errorMessage='#{error_msg}'/>")
      described_class.send(:request_params, mock_request, druid, process_name, error_msg)
      expect(headers_hash).to eq("content-type" => "application/xml")
    end

    it 'escapes special characters in error message' do
      error_msg = "Invalid moab, validation errors: [\"Version directory name not in 'v00xx' format: original-v1\"]"
      expected_error_msg = CGI.escapeHTML(error_msg)
      allow(mock_request).to receive(:url)
      expect(mock_request).to receive(:body=).with("<process name='#{process_name}' status='error' errorMessage='#{expected_error_msg}'/>")
      described_class.send(:request_params, mock_request, druid, process_name, error_msg)
    end
  end
end
