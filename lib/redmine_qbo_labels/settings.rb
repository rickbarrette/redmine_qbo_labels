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
  # The plugin's settings (Administration » Plugins » Redmine QBO Labels plugin » Configure)
  module Settings
    DEFAULTS = {
      # Labels run along a 62mm (2.4in) continuous roll; their length fits the text, between these (inches)
      'max_length_in' => '4',
      'min_length_in' => '1',
      'uppercase' => '1',
      # A label still waiting this long (the agent is offline) is dropped, so it doesn't print hours later
      'job_expiry_minutes' => '10',
      # How often the print agent asks for labels (seconds)
      'poll_seconds' => '2',
      # Write the agent's polls and the print dialog's status checks to the Redmine log (for debugging)
      'log_requests' => '0'
    }.freeze

    MM_PER_INCH = 25.4

    def self.values
      DEFAULTS.merge((Setting.plugin_redmine_qbo_labels.presence || {}).to_h.stringify_keys)
    end

    def self.max_length_in
      clamp(values['max_length_in'], DEFAULTS['max_length_in'], 1.0, 12.0)
    end

    def self.min_length_in
      [clamp(values['min_length_in'], DEFAULTS['min_length_in'], 0.5, 12.0), max_length_in].min
    end

    def self.max_length_mm
      (max_length_in * MM_PER_INCH).round(1)
    end

    def self.min_length_mm
      (min_length_in * MM_PER_INCH).round(1)
    end

    def self.uppercase?
      values['uppercase'].to_s == '1'
    end

    def self.job_expiry
      clamp(values['job_expiry_minutes'], DEFAULTS['job_expiry_minutes'], 1, 1440).minutes
    end

    def self.poll_seconds
      clamp(values['poll_seconds'], DEFAULTS['poll_seconds'], 1, 60)
    end

    def self.log_requests?
      values['log_requests'].to_s == '1'
    end

    def self.clamp(value, default, min, max)
      number = Float(value.to_s, exception: false) || Float(default)
      number = number.clamp(min, max)
      min.is_a?(Integer) ? number.round : number
    end
    private_class_method :clamp
  end
end
