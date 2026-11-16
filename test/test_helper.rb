#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Load the Redmine helper
require File.expand_path('../../../test/test_helper', __dir__)

module QboLabelsTestHelper
  # Start from no printers or labels (inside the test's transaction)
  def self.included(base)
    base.setup do
      LabelJob.delete_all
      LabelPrinter.delete_all
    end
  end

  def create_printer(name: 'Parts room', active: true)
    printer = LabelPrinter.new(name: name, active: active)
    token = printer.generate_token
    printer.save!
    [printer, token]
  end

  def create_job(printer, lines: %w[SMITH E1234], status: 'queued', user: User.find(2), **attributes)
    LabelJob.create!({ label_printer: printer, user: user, lines: lines, status: status }.merge(attributes))
  end

  # A customer, without sending it to QuickBooks
  def create_customer(id: 9001, name: 'Jane Smith')
    customer = Customer.new(id: id, name: name)
    customer.skip_qbo_push = true
    customer.save!
    customer
  end

  def create_estimate(customer, id: '8001', doc_number: '1234', txn_date: Date.new(2026, 11, 2))
    Estimate.create!(id: id, doc_number: doc_number, txn_date: txn_date, customer: customer)
  end

  def with_label_settings(values)
    saved = Setting.plugin_redmine_qbo_labels
    Setting.plugin_redmine_qbo_labels = RedmineQboLabels::Settings::DEFAULTS.merge(values)
    yield
  ensure
    Setting.plugin_redmine_qbo_labels = saved
  end
end
