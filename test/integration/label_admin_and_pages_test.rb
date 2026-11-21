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
require File.expand_path('../../../redmine_qbo/test/qbo_fake_service', __dir__)

# Managing printers, the print dialog's limits, and Print label on other plugins' pages
class LabelAdminAndPagesTest < Redmine::IntegrationTest
  include QboLabelsTestHelper
  include QboFakeServiceHelper
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
           :projects_trackers, :issue_statuses, :enabled_modules, :enumerations, :workflows

  # ---- printers ----

  def test_a_printer_needs_a_unique_name
    create_printer
    log_user('admin', 'admin')
    get '/label_printers/new'
    assert_response :success
    assert_no_difference('LabelPrinter.count') do
      post '/label_printers', params: { label_printer: { name: 'parts ROOM', active: '1' } }
    end
    assert_response :success
    assert_select '#errorExplanation'
  end

  def test_editing_and_deleting_a_printer
    printer, token = create_printer
    create_job(printer)
    log_user('admin', 'admin')
    get "/label_printers/#{printer.id}/edit"
    assert_response :success
    patch "/label_printers/#{printer.id}", params: { label_printer: { name: 'Front desk', active: '0' } }
    assert_redirected_to '/label_printers'
    assert_equal 'Front desk', printer.reload.name
    assert_nil LabelPrinter.authenticate(token)

    patch "/label_printers/#{printer.id}", params: { label_printer: { name: '' } }
    assert_response :success
    assert_select '#errorExplanation'

    delete "/label_printers/#{printer.id}"
    assert_redirected_to '/label_printers'
    assert_equal 0, LabelJob.count
    get "/label_printers/#{printer.id}/edit"
    assert_response :not_found
  end

  def test_the_printers_page_lists_recent_labels_and_expires_lapsed_ones
    printer, = create_printer
    lapsed = create_job(printer, lines: ['LAPSED'])
    lapsed.update_columns(created_at: 1.hour.ago)
    create_job(printer, lines: ['WAITING'])
    log_user('admin', 'admin')
    get '/label_printers'
    assert_response :success
    assert_includes response.body, 'LAPSED'
    assert_includes response.body, 'WAITING'
    assert_equal 'expired', lapsed.reload.status
  end

  # ---- the print dialog ----

  def test_copies_and_printer
    front, = create_printer(name: 'Front desk')
    parts, = create_printer(name: 'Parts room')
    create_printer(name: 'Old', active: false)
    Role.find(1).add_permission!(:print_labels)
    log_user('jsmith', 'jsmith')
    post '/label_jobs', params: { lines: ['Parts'], copies: '50', printer_id: parts.id }, xhr: true
    assert_equal [parts, LabelJob::MAX_COPIES], [LabelJob.last.label_printer, LabelJob.last.copies]

    # An unknown or inactive printer: the first active one (by name)
    post '/label_jobs', params: { lines: ['Parts'], copies: '0', printer_id: LabelPrinter.find_by(name: 'Old').id }, xhr: true
    assert_equal [front, 1], [LabelJob.last.label_printer, LabelJob.last.copies]
  end

  def test_no_printer_no_label
    create_printer(active: false)
    Role.find(1).add_permission!(:print_labels)
    log_user('jsmith', 'jsmith')
    assert_no_difference('LabelJob.count') do
      post '/label_jobs', params: { lines: ['Parts'] }, xhr: true
    end
    assert_response :success
  end

  def test_admins_can_follow_any_label
    printer, = create_printer
    job = create_job(printer, user: User.find(2))
    log_user('admin', 'admin')
    get "/label_jobs/#{job.id}", headers: { 'Accept' => 'application/json' }
    assert_response :success
    assert_equal false, response.parsed_body['printer_online']
    get '/label_jobs/424242', headers: { 'Accept' => 'application/json' }
    assert_response :not_found
  end

  # ---- other pages ----

  def test_the_customer_page_sidebar_prints_for_the_customer
    create_printer
    install_fake_quickbooks
    customer = create_customer
    Role.find(1).add_permission!(:print_labels)
    Role.find(1).add_permission!(:view_customers)
    log_user('jsmith', 'jsmith')
    get "/customers/#{customer.id}"
    assert_response :success
    assert_select '#sidebar .qbo-label-sidebar a[href=?]', "/label_jobs/new?source_id=#{customer.id}&source_type=customer"
    assert_select '#sidebar .qbo-label-sidebar', text: /Jane Smith/
  end

  def test_the_appointment_page_sidebar_prints_for_the_appointment
    skip 'redmine_qbo_calendar is not installed' unless Redmine::Plugin.installed?(:redmine_qbo_calendar)

    create_printer
    appointment = CustomerAppointment.new(subject: 'Lift kit install', description: '', date: Time.utc(2026, 11, 24, 9), user_id: 2)
    appointment.save!(validate: false)
    Role.find(1).add_permission!(:print_labels)
    Role.find(1).add_permission!(:view_customer_appointments)
    log_user('jsmith', 'jsmith')
    get "/customer_appointments/#{appointment.id}"
    assert_response :success
    assert_select '#sidebar .qbo-label-sidebar a[href=?]', "/label_jobs/new?source_id=#{appointment.id}&source_type=appointment"
    assert_select '#sidebar .qbo-label-sidebar', text: /Lift kit install/
  end

  def test_estimate_and_invoice_links
    hook = RedmineQboLabels::Hooks::ViewHookListener.instance
    create_printer
    Role.find(1).add_permission!(:print_labels)
    User.current = User.find(2)
    caller = Object.new
    def caller.render(partial:, locals:)
      "#{partial} #{locals[:source_type]} #{locals[:source_id]}"
    end
    assert_equal 'label_hooks/print_link estimate 8001', hook.view_qbo_estimate_contextual(hook_caller: caller, estimate_id: '8001')
    assert_equal 'label_hooks/print_link invoice 9001', hook.view_qbo_invoice_contextual(hook_caller: caller, invoice_id: '9001')
    assert_equal '', hook.view_qbo_invoice_contextual(hook_caller: caller, invoice_id: '')
    User.current = User.find(3)
    assert_equal '', hook.view_qbo_estimate_contextual(hook_caller: caller, estimate_id: '8001')
  ensure
    User.current = nil
  end

  def test_the_dialog_assets_are_for_signed_in_users
    get '/projects'
    assert_no_match(/qbo_labels\.js/, response.body)
    log_user('jsmith', 'jsmith')
    get '/projects'
    assert_match(/qbo_labels.*\.js/, response.body)
  end
end
