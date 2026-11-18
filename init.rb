Redmine::Plugin.register :redmine_qbo_labels do

  # About
  name 'Redmine QBO Labels plugin'
  author 'Rick Barrette'
  description 'Prints part labels (customer last name and document number) for issues, estimates and invoices on a Brother QL label printer, through a small print agent on the printer\'s network'
  version '2026.11.1'
  url 'https://github.com/rickbarrette/redmine_qbo_labels'
  author_url 'https://barrettefabrication.com'
  requires_redmine version_or_higher: '7.0.0'

  # Customers, estimates and invoices live in redmine_qbo
  begin
    requires_redmine_plugin :redmine_qbo, version_or_higher: '2026.11.0'
  rescue Redmine::PluginNotFound
    raise 'Please install the redmine_qbo plugin (https://github.com/rickbarrette/redmine_qbo)'
  end

  settings default: RedmineQboLabels::Settings::DEFAULTS.dup, partial: 'settings/qbo_labels'

  # Print label dialog, sending the label and following its print job
  permission :print_labels, { label_jobs: [:new, :create, :show] }, global: true

  # Label printers (print agents) and their recent jobs
  menu :admin_menu, :label_printers, { controller: 'label_printers', action: 'index' },
       caption: :label_label_printer_plural, icon: 'qbo-label-print', plugin: :redmine_qbo_labels, html: { class: 'icon' }
end

RedmineQboLabels.setup
