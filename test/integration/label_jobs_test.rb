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

class LabelJobsTest < Redmine::IntegrationTest
  include QboLabelsTestHelper
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
           :projects_trackers, :issue_statuses, :enabled_modules, :enumerations, :workflows

  def setup
    @printer, = create_printer
    Role.find(1).add_permission!(:print_labels)
  end

  def test_print_dialog_for_an_issue
    log_user('jsmith', 'jsmith')
    get '/label_jobs/new', params: { source_type: 'issue', source_id: 1 }, xhr: true
    assert_response :success
    assert_includes response.body, 'W1'
    assert_includes response.body, 'qbo-label-preview'
  end

  def test_printing_needs_the_permission
    log_user('dlopper', 'foo') # Developer: no Print labels
    get '/label_jobs/new', params: { source_type: 'issue', source_id: 1 }, xhr: true
    assert_response :forbidden
  end

  def test_print_dialog_for_something_unseen
    log_user('jsmith', 'jsmith')
    get '/label_jobs/new', params: { source_type: 'issue', source_id: 999 }, xhr: true
    assert_response :not_found
  end

  def test_print_queues_the_label
    log_user('jsmith', 'jsmith')
    assert_difference 'LabelJob.count', 1 do
      post '/label_jobs', params: { source_type: 'issue', source_id: 1, lines: ['Smith', 'w1'], copies: '2' }, xhr: true
    end
    assert_response :success
    job = LabelJob.last
    assert_equal %w[SMITH W1], job.lines
    assert_equal 2, job.copies
    assert_equal @printer, job.label_printer
    assert_equal 'issue', job.source_type
    assert_equal '1', job.source_id
    assert_includes response.body, "QboLabels.follow"

    get "/label_jobs/#{job.id}", headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal 'queued', response.parsed_body['status']
    assert_equal false, response.parsed_body['finished']
  end

  def test_an_empty_label_shows_the_dialog_again
    log_user('jsmith', 'jsmith')
    assert_no_difference 'LabelJob.count' do
      post '/label_jobs', params: { source_type: 'issue', source_id: 1, lines: ['', ' '] }, xhr: true
    end
    assert_response :success
    assert_includes response.body, 'errorExplanation'
  end

  def test_only_your_own_labels_can_be_followed
    job = create_job(@printer, user: User.find(3))
    log_user('jsmith', 'jsmith')
    get "/label_jobs/#{job.id}", headers: { "Accept" => "application/json" }
    assert_response :not_found
  end

  def test_issue_page_has_the_print_label_link
    log_user('jsmith', 'jsmith')
    get '/issues/1'
    assert_response :success
    assert_select 'template#qbo-label-issue-link a.icon-qbo-label-print[data-remote=true]'
  end

  def test_sidebar_prints_for_the_work_order_on_its_page
    log_user('jsmith', 'jsmith')
    get '/issues/1'
    assert_select '#sidebar .qbo-label-sidebar a.icon-qbo-label-print[href=?]', '/label_jobs/new?source_id=1&source_type=issue'
    assert_select '#sidebar .qbo-label-sidebar', text: /Work order #1/
  end

  def test_sidebar_prints_a_blank_label_elsewhere
    log_user('jsmith', 'jsmith')
    get '/projects'
    assert_select '#sidebar .qbo-label-sidebar a.icon-qbo-label-print[href=?]', '/label_jobs/new'
  end

  def test_blank_label_dialog_and_print
    log_user('jsmith', 'jsmith')
    get '/label_jobs/new', xhr: true
    assert_response :success
    assert_no_match(/qbo_label_po_numbers/, response.body)

    post '/label_jobs', params: { source_type: '', source_id: '', lines: ['Parts', 'Bin 4'] }, xhr: true
    job = LabelJob.last
    assert_equal ['PARTS', 'BIN 4'], job.lines
    assert_nil job.source_type
  end

  def test_no_link_without_an_active_printer
    @printer.update!(active: false)
    log_user('jsmith', 'jsmith')
    get '/issues/1'
    assert_select 'template#qbo-label-issue-link', 0
    assert_select '.qbo-label-sidebar', 0
  end
end
