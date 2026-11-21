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

class LabelSettingsTest < ActiveSupport::TestCase
  include QboLabelsTestHelper

  Settings = RedmineQboLabels::Settings

  def test_defaults
    with_label_settings({}) do
      assert_equal 4.0, Settings.max_length_in
      assert_equal 1.0, Settings.min_length_in
      assert_equal 101.6, Settings.max_length_mm
      assert_equal 25.4, Settings.min_length_mm
      assert Settings.uppercase?
      assert_equal 10.minutes, Settings.job_expiry
      assert_equal 2, Settings.poll_seconds
      assert_not Settings.log_requests?
    end
  end

  def test_values_are_kept_in_range
    with_label_settings('max_length_in' => '20', 'min_length_in' => '0.1', 'job_expiry_minutes' => '0',
                        'poll_seconds' => '600') do
      assert_equal 12.0, Settings.max_length_in
      assert_equal 0.5, Settings.min_length_in
      assert_equal 1.minute, Settings.job_expiry
      assert_equal 60, Settings.poll_seconds
    end
  end

  def test_the_shortest_label_is_never_longer_than_the_longest
    with_label_settings('max_length_in' => '2', 'min_length_in' => '3') do
      assert_equal 2.0, Settings.min_length_in
    end
  end

  def test_bad_numbers_use_the_defaults
    with_label_settings('max_length_in' => 'long', 'poll_seconds' => '', 'job_expiry_minutes' => '2.6') do
      assert_equal 4.0, Settings.max_length_in
      assert_equal 2, Settings.poll_seconds
      assert_equal 3.minutes, Settings.job_expiry
    end
  end

  def test_no_saved_settings
    saved = Setting.plugin_redmine_qbo_labels
    Setting.plugin_redmine_qbo_labels = nil
    assert_equal Settings::DEFAULTS, Settings.values
  ensure
    Setting.plugin_redmine_qbo_labels = saved
  end
end
