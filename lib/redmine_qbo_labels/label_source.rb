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
  # What goes on a part label: the customer's last name and the PO number parts are ordered with (Sales SOP):
  # E + estimate number, I + invoice number, W + work order (issue) number.
  #
  # From an issue, estimate or invoice, both lines are filled in; from a customer, their name (with their
  # estimates, invoices and open work orders offered as PO numbers); from an appointment (redmine_qbo_calendar),
  # its customer and its estimate. A blank label (no type) is for anything else.
  class LabelSource
    TYPES = %w[issue estimate invoice customer appointment].freeze
    PREFIXES = { 'issue' => 'W', 'estimate' => 'E', 'invoice' => 'I' }.freeze
    NAME_SUFFIXES = /\A(jr|sr|ii|iii|iv|v|esq)\.?\z/i
    # PO numbers offered in the print dialog, of each kind
    SUGGESTIONS = 8

    attr_reader :type, :record

    # The record of that type the current user may see (as a LabelSource), or nil. No type: a blank label.
    def self.find(type, id)
      type = type.to_s
      return blank if type.empty?
      return nil unless TYPES.include?(type)

      record = case type
               when 'issue' then Issue.visible.find_by(id: id)
               when 'estimate' then Estimate.find_by(id: id) if billing_visible?(:write_estimates)
               when 'invoice' then Invoice.find_by(id: id) if billing_visible?(:write_invoices)
               when 'customer' then Customer.find_by(id: id) if customers_visible?
               when 'appointment' then find_appointment(id)
               end
      record && new(type, record)
    end

    def self.blank
      new(nil, nil)
    end

    def self.find_appointment(id)
      return nil unless defined?(CustomerAppointment) &&
                        User.current.allowed_to?(:view_customer_appointments, nil, global: true)

      CustomerAppointment.find_by(id: id)
    end
    private_class_method :find_appointment

    # Estimates and invoices are seen by those who view customers or write them (redmine_qbo's permissions)
    def self.billing_visible?(write_permission, user = User.current)
      [:view_customers, write_permission].any? { |permission| user.allowed_to?(permission, nil, global: true) }
    end

    def self.customers_visible?(user = User.current)
      user.allowed_to?(:view_customers, nil, global: true)
    end
    private_class_method :customers_visible?

    def initialize(type, record)
      @type = type
      @record = record
    end

    def blank?
      record.nil?
    end

    def id
      record&.id
    end

    def customer
      return nil if blank?
      return record if type == 'customer'

      record.respond_to?(:customer) ? record.customer : nil
    end

    # E1234, I1234 or W1234 (an appointment's is its estimate's); blank for a customer or a blank label
    def po_number
      case type
      when 'issue' then "W#{record.id}"
      when 'estimate', 'invoice' then "#{PREFIXES[type]}#{record.doc_number}"
      when 'appointment' then record.estimate ? "E#{record.estimate.doc_number}" : ''
      else ''
      end
    end

    def last_name
      self.class.last_name(customer)
    end

    # The label's lines, as they are printed unless changed in the print dialog
    def lines
      [last_name, po_number]
    end

    # The customer's estimates, invoices and open work orders the user may see, newest first, as
    # [[po_number, description]], offered for the PO number in the print dialog
    def po_suggestions
      customer = self.customer
      return [] unless customer

      suggestions = []
      if self.class.billing_visible?(:write_estimates)
        customer.estimates.where.not(doc_number: [nil, '']).order(txn_date: :desc).limit(SUGGESTIONS).each do |estimate|
          suggestions << ["E#{estimate.doc_number}", describe(:label_qbo_labels_source_estimate, estimate.txn_date)]
        end
      end
      if self.class.billing_visible?(:write_invoices)
        customer.invoices.where.not(doc_number: [nil, '']).order(txn_date: :desc).limit(SUGGESTIONS).each do |invoice|
          suggestions << ["I#{invoice.doc_number}", describe(:label_qbo_labels_source_invoice, invoice.txn_date)]
        end
      end
      Issue.visible.open.where(customer_id: customer.id).order(id: :desc).limit(SUGGESTIONS).each do |issue|
        suggestions << ["W#{issue.id}", issue.subject.to_s.truncate(50)]
      end
      suggestions.uniq(&:first)
    end

    # What it's for, e.g. "Estimate #1234", "Customer Jane Smith"; nil for a blank label
    def title
      case type
      when nil then nil
      when 'issue' then "#{I18n.t(:label_qbo_labels_source_issue)} ##{record.id}"
      when 'estimate', 'invoice' then "#{I18n.t("label_qbo_labels_source_#{type}")} ##{record.doc_number}"
      when 'customer' then "#{I18n.t(:label_qbo_labels_source_customer)} #{record.name}"
      when 'appointment' then "#{I18n.t(:label_qbo_labels_source_appointment)} ##{record.id}"
      end
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

    private

    def describe(label, date)
      [I18n.t(label), date.respond_to?(:strftime) ? I18n.l(date.to_date) : date].compact_blank.join(' ')
    end
  end
end
