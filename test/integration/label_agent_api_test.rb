#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.expand_path('../test_helper', __dir__)

class LabelAgentApiTest < Redmine::IntegrationTest
  include QboLabelsTestHelper
  fixtures :users

  def setup
    @printer, @token = create_printer
  end

  def headers(token = @token)
    { 'Authorization' => "Bearer #{token}", 'CONTENT_TYPE' => 'application/json' }
  end

  def test_unknown_token_is_refused
    post '/label_agent/poll', params: '{}', headers: headers('qbl_wrong')
    assert_response :unauthorized
    post '/label_agent/poll', params: '{}'
    assert_response :unauthorized
  end

  def test_poll_without_labels
    post '/label_agent/poll', params: '{}', headers: headers
    assert_response :success
    json = response.parsed_body
    assert_nil json['job']
    assert_equal 2, json['poll_seconds']
    assert @printer.reload.online?
  end

  def test_poll_hands_out_the_next_label
    job = create_job(@printer, copies: 2)
    post '/label_agent/poll', params: '{}', headers: headers
    assert_response :success
    json = response.parsed_body['job']
    assert_equal job.id, json['id']
    assert_equal %w[SMITH E1234], json['lines']
    assert_equal 2, json['copies']
    assert_equal 'printing', job.reload.status

    post '/label_agent/poll', params: '{}', headers: headers
    assert_nil response.parsed_body['job']
  end

  def test_poll_records_what_the_agent_says
    post '/label_agent/poll', headers: headers,
         params: { agent: { version: '2026.11.0', printer_model: 'QL-820NWB', printer_address: '192.168.0.100:9100',
                            printer_status: 'Ready, 62mm continuous', other: 'x' } }.to_json
    assert_response :success
    @printer.reload
    assert_equal '2026.11.0', @printer.agent_version
    assert_equal 'QL-820NWB', @printer.printer_model
    assert_equal 'Ready, 62mm continuous', @printer.printer_status
  end

  def test_result_marks_the_label_printed_or_failed
    job = create_job(@printer)
    LabelJob.claim_next(@printer)
    post "/label_agent/jobs/#{job.id}/result", params: { status: 'printed' }.to_json, headers: headers
    assert_response :success
    assert_equal 'printed', job.reload.status

    # A repeated report changes nothing
    post "/label_agent/jobs/#{job.id}/result", params: { status: 'failed', error: 'x' }.to_json, headers: headers
    assert_response :success
    assert_equal 'printed', job.reload.status

    job = create_job(@printer)
    post "/label_agent/jobs/#{job.id}/result", params: { status: 'failed', error: 'Error: No media' }.to_json,
                                               headers: headers
    assert_equal 'failed', job.reload.status
    assert_equal 'Error: No media', job.error
  end

  def test_an_agent_only_reports_on_its_own_printers_labels
    other, = create_printer(name: 'Shop')
    job = create_job(other)
    post "/label_agent/jobs/#{job.id}/result", params: { status: 'printed' }.to_json, headers: headers
    assert_response :not_found
    assert_equal 'queued', job.reload.status
  end

  def test_polls_stay_out_of_the_log_unless_turned_on
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    previous = Rails.logger
    Rails.logger = ActiveSupport::BroadcastLogger.new(logger)
    begin
      post '/label_agent/poll', params: '{}', headers: headers
      assert_not_includes io.string, '/label_agent/poll'

      with_label_settings('log_requests' => '1') do
        post '/label_agent/poll', params: '{}', headers: headers
      end
      assert_includes io.string, 'Parts room agent'
    ensure
      Rails.logger = previous
    end
  end
end
