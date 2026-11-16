#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQboLabels
  # What goes on a part label for an issue, estimate or invoice: the customer's last name and the PO number
  # parts are ordered with (Sales SOP): E + estimate number, I + invoice number, W + work order (issue) number
  class LabelSource
    TYPES = %w[issue estimate invoice].freeze
    PREFIXES = { 'issue' => 'W', 'estimate' => 'E', 'invoice' => 'I' }.freeze
    NAME_SUFFIXES = /\A(jr|sr|ii|iii|iv|v|esq)\.?\z/i

    attr_reader :type, :record

    # The issue, estimate or invoice the current user may see, or nil
    def self.find(type, id)
      type = type.to_s
      return nil unless TYPES.include?(type)

      record = case type
               when 'issue' then Issue.visible.find_by(id: id)
               when 'estimate' then Estimate.find_by(id: id) if billing_visible?(:write_estimates)
               when 'invoice' then Invoice.find_by(id: id) if billing_visible?(:write_invoices)
               end
      record && new(type, record)
    end

    # Estimates and invoices are seen by those who view customers or write them (redmine_qbo's permissions)
    def self.billing_visible?(write_permission, user = User.current)
      [:view_customers, write_permission].any? { |permission| user.allowed_to?(permission, nil, global: true) }
    end
    private_class_method :billing_visible?

    def initialize(type, record)
      @type = type
      @record = record
    end

    def id
      record.id
    end

    def customer
      record.respond_to?(:customer) ? record.customer : nil
    end

    # E1234, I1234 or W1234
    def po_number
      number = type == 'issue' ? record.id : record.doc_number
      "#{PREFIXES[type]}#{number}"
    end

    def last_name
      self.class.last_name(customer)
    end

    # The label's lines, as they are printed unless changed in the print dialog
    def lines
      [last_name, po_number]
    end

    # Shown in the job list: "Estimate #1234"
    def title
      number = type == 'issue' ? record.id : record.doc_number
      "#{I18n.t("label_qbo_labels_source_#{type}")} ##{number}"
    end

    # The customer's last name: their family name in QuickBooks, or for a business their full name, or else
    # the last word of their name (skipping Jr., III, ...)
    def self.last_name(customer)
      return '' unless customer

      details = qbo_details(customer)
      family = details&.family_name.to_s.strip
      return family if family.present?
      return customer.name.to_s if details&.company_name.present?

      words = customer.name.to_s.split
      words.pop while words.size > 1 && words.last.match?(NAME_SUFFIXES)
      words.last.to_s
    end

    # QuickBooks' copy of the customer (cached by redmine_qbo); nil when QuickBooks can't be reached
    def self.qbo_details(customer)
      customer.details
    rescue StandardError => e
      Rails.logger.warn "[redmine_qbo_labels] QuickBooks details for customer #{customer.id}: #{e.message}"
      nil
    end
    private_class_method :qbo_details
  end
end
