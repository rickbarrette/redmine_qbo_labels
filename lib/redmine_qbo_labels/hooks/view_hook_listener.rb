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
  module Hooks
    # "Print label" in the top-right actions of issues, estimates and invoices, and in the sidebar of every page
    class ViewHookListener < Redmine::Hook::ViewListener
      # Pages the sidebar's Print label fills the label from: [controller, action] => how to find the record
      SIDEBAR_SOURCES = {
        %w[issues show] => ['issue', ->(c) { c.instance_variable_get(:@issue) }],
        %w[qbo_estimates edit] => ['estimate', ->(c) { c.instance_variable_get(:@form) }],
        %w[qbo_invoices edit] => ['invoice', ->(c) { c.instance_variable_get(:@form) }],
        %w[customers show] => ['customer', ->(c) { c.instance_variable_get(:@customer) }],
        %w[customer_appointments show] => ['appointment', ->(c) { c.instance_variable_get(:@appointment) }]
      }.freeze

      # The print dialog's script and styles
      def view_layouts_base_html_head(context = {})
        return '' unless User.current.logged?

        stylesheet_link_tag('qbo_labels', plugin: 'redmine_qbo_labels') +
          javascript_include_tag('qbo_labels', plugin: 'redmine_qbo_labels')
      end

      # An estimate's page (redmine_qbo's :view_qbo_estimate_contextual)
      def view_qbo_estimate_contextual(context = {})
        print_link(context, 'estimate', context[:estimate_id])
      end

      # An invoice's page (redmine_qbo's :view_qbo_invoice_contextual)
      def view_qbo_invoice_contextual(context = {})
        print_link(context, 'invoice', context[:invoice_id])
      end

      # An issue's page: Redmine has no hook in the issue's actions, so the link is moved there by script
      def view_issues_show_details_bottom(context = {})
        issue = context[:issue]
        return '' unless issue&.persisted? && RedmineQboLabels.printing_available?

        context[:hook_caller].render(partial: 'label_hooks/issue_print_link', locals: { issue: issue })
      end

      # The sidebar's Labels section: Print label for what the page shows (a customer, estimate, invoice,
      # appointment or work order), or a blank label anywhere else
      def view_layouts_base_sidebar(context = {})
        return '' unless RedmineQboLabels.printing_available?

        source_type, record = sidebar_source(context[:controller])
        context[:hook_caller].render(partial: 'label_hooks/sidebar',
                                     locals: { source_type: source_type, source_id: record&.id,
                                               title: sidebar_title(source_type, record) })
      end

      private

      def sidebar_source(controller)
        return [nil, nil] unless controller

        type, finder = SIDEBAR_SOURCES[[controller.controller_name, controller.action_name]]
        record = finder&.call(controller)
        record&.id.present? ? [type, record] : [nil, nil]
      end

      # What the page shows, from what the page already loaded (no QuickBooks lookups on every page)
      def sidebar_title(source_type, record)
        case source_type
        when 'issue' then "#{l(:label_qbo_labels_source_issue)} ##{record.id}"
        when 'estimate', 'invoice' then "#{l("label_qbo_labels_source_#{source_type}")} ##{record.doc_number}"
        when 'customer' then record.name
        when 'appointment' then record.try(:subject).presence || "#{l(:label_qbo_labels_source_appointment)} ##{record.id}"
        end
      end

      def print_link(context, source_type, source_id)
        return '' if source_id.blank? || !RedmineQboLabels.printing_available?

        context[:hook_caller].render(partial: 'label_hooks/print_link',
                                     locals: { source_type: source_type, source_id: source_id })
      end
    end
  end
end
