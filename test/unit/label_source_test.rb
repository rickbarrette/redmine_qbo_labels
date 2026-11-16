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

class LabelSourceTest < ActiveSupport::TestCase
  include QboLabelsTestHelper
  fixtures :projects, :users, :members, :member_roles, :roles, :issues, :trackers, :projects_trackers,
           :issue_statuses, :enabled_modules, :enumerations

  Details = Struct.new(:family_name, :company_name)
  FakeCustomer = Struct.new(:id, :name, :details)
  Document = Struct.new(:id, :doc_number, :customer)

  def customer(name, family_name: nil, company_name: nil)
    FakeCustomer.new(1, name, Details.new(family_name, company_name))
  end

  def test_po_numbers_follow_the_sales_sop
    assert_equal 'E1234', RedmineQboLabels::LabelSource.new('estimate', Document.new(99, '1234', nil)).po_number
    assert_equal 'I1234', RedmineQboLabels::LabelSource.new('invoice', Document.new(98, '1234', nil)).po_number
    assert_equal 'W3', RedmineQboLabels::LabelSource.new('issue', Issue.find(3)).po_number
  end

  def test_last_name_is_the_quickbooks_family_name
    assert_equal 'Smith', RedmineQboLabels::LabelSource.last_name(customer('Jane A. Smith-Jones', family_name: 'Smith'))
  end

  def test_last_name_falls_back_to_the_last_word_of_the_name
    assert_equal 'Smith', RedmineQboLabels::LabelSource.last_name(customer('Jane Smith'))
    assert_equal 'Smith', RedmineQboLabels::LabelSource.last_name(customer('John Smith Jr.'))
    assert_equal 'Smith', RedmineQboLabels::LabelSource.last_name(customer('John Smith III'))
    assert_equal 'Smith', RedmineQboLabels::LabelSource.last_name(customer('Smith'))
  end

  def test_a_business_uses_its_whole_name
    assert_equal 'Acme Offroad LLC',
                 RedmineQboLabels::LabelSource.last_name(customer('Acme Offroad LLC', company_name: 'Acme Offroad LLC'))
  end

  def test_last_name_without_quickbooks
    broken = FakeCustomer.new(1, 'Jane Smith', nil)
    def broken.details = raise('QuickBooks is down')
    assert_equal 'Smith', RedmineQboLabels::LabelSource.last_name(broken)
    assert_equal '', RedmineQboLabels::LabelSource.last_name(nil)
  end

  def test_issues_must_be_visible
    User.current = User.find(2)
    assert RedmineQboLabels::LabelSource.find('issue', 1)
    User.current = User.anonymous
    assert_nil RedmineQboLabels::LabelSource.find('issue', 4) # private project
    assert_nil RedmineQboLabels::LabelSource.find('project', 1)
  ensure
    User.current = nil
  end

  def test_a_blank_label
    source = RedmineQboLabels::LabelSource.find('', nil)
    assert source.blank?
    assert_equal ['', ''], source.lines
    assert_nil source.title
    assert_empty source.po_suggestions
  end

  def test_a_customer_fills_in_the_name_and_suggests_po_numbers
    customer = create_customer
    create_estimate(customer, id: '8001', doc_number: '1234', txn_date: Date.new(2026, 11, 2))
    create_estimate(customer, id: '8002', doc_number: '1240', txn_date: Date.new(2026, 11, 9))
    Issue.find(1).update_column(:customer_id, customer.id)
    User.current = User.find(1) # admin

    source = RedmineQboLabels::LabelSource.find('customer', customer.id)
    assert_equal ['Smith', ''], source.lines
    numbers = source.po_suggestions.map(&:first)
    assert_equal %w[E1240 E1234 W1], numbers
  ensure
    User.current = nil
  end

  def test_estimates_from_the_record
    customer = create_customer
    estimate = create_estimate(customer)
    User.current = User.find(1)
    source = RedmineQboLabels::LabelSource.find('estimate', estimate.id)
    assert_equal %w[Smith E1234], source.lines
    assert_equal 'Estimate #1234', source.title
    assert_includes source.po_suggestions.map(&:first), 'E1234'
  ensure
    User.current = nil
  end

  def test_customers_need_view_customers
    customer = create_customer
    User.current = User.find(7)
    assert_nil RedmineQboLabels::LabelSource.find('customer', customer.id)
  ensure
    User.current = nil
  end

  def test_estimates_and_invoices_need_redmine_qbos_permissions
    User.current = User.find(7) # no global permissions
    assert_nil RedmineQboLabels::LabelSource.find('estimate', 1)
    assert_nil RedmineQboLabels::LabelSource.find('invoice', 1)
  ensure
    User.current = nil
  end
end
