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
  # Prepended to Rails::Rack::Logger: the print agent asks for labels every couple of seconds, and the print
  # dialog checks on its label every second, which would fill the log. Those requests are only logged (and
  # their SQL) when "Log label printer requests" is on; warnings (e.g. an agent with a wrong token) and errors
  # are always logged.
  module RequestSilencer
    QUIET_PATHS = %r{\A/(label_agent/|label_jobs/\d+(\.json)?\z)}

    def call(env)
      return super unless quiet?(env)

      logger.silence(::Logger::WARN) { super }
    end

    private

    def quiet?(env)
      env['PATH_INFO'].to_s.match?(QUIET_PATHS) && !RedmineQboLabels::Settings.log_requests?
    rescue StandardError
      false
    end
  end
end
