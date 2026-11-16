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

class LabelJobTest < ActiveSupport::TestCase
  include QboLabelsTestHelper
  fixtures :users

  def setup
    @printer, = create_printer
  end

  def test_lines_are_tidied_and_capitalized
    job = create_job(@printer, lines: ['  Smith ', '', 'e1234'])
    assert_equal %w[SMITH E1234], job.lines
    assert_equal %w[SMITH E1234], job.reload.lines
  end

  def test_capitals_can_be_turned_off
    with_label_settings('uppercase' => '0') do
      assert_equal %w[Smith E1234], create_job(@printer, lines: %w[Smith E1234]).lines
    end
  end

  def test_a_label_needs_text_that_fits
    assert_not LabelJob.new(label_printer: @printer, lines: ['', ' ']).valid?
    assert_not LabelJob.new(label_printer: @printer, lines: ['X' * 41]).valid?
    assert_not LabelJob.new(label_printer: @printer, lines: %w[A B C D E]).valid?
    assert_not LabelJob.new(label_printer: @printer, lines: %w[A], copies: 11).valid?
    assert LabelJob.new(label_printer: @printer, lines: %w[A], copies: 10).valid?
  end

  def test_claim_next_takes_the_oldest_queued_label_of_the_printer
    other, = create_printer(name: 'Shop')
    first = create_job(@printer)
    second = create_job(@printer)
    create_job(other)

    assert_equal first, LabelJob.claim_next(@printer)
    assert_equal 'printing', first.reload.status
    assert_not_nil first.claimed_at
    assert_equal second, LabelJob.claim_next(@printer)
    assert_nil LabelJob.claim_next(@printer)
  end

  def test_labels_not_picked_up_in_time_expire
    job = create_job(@printer)
    travel 11.minutes do
      assert_nil LabelJob.claim_next(@printer)
      job.reload
      assert_equal 'expired', job.status
      assert job.finished?
      assert_not_nil job.error
    end
  end

  def test_expiry_follows_the_setting
    job = create_job(@printer)
    with_label_settings('job_expiry_minutes' => '30') do
      travel 11.minutes do
        assert_equal job, LabelJob.claim_next(@printer)
      end
    end
  end

  def test_labels_the_agent_never_reports_on_fail
    job = create_job(@printer)
    LabelJob.claim_next(@printer)
    travel 3.minutes do
      LabelJob.expire_lapsed
      assert_equal 'failed', job.reload.status
    end
  end

  def test_old_labels_are_removed
    job = create_job(@printer, status: 'printed')
    travel 31.days do
      LabelJob.expire_lapsed
      assert_not LabelJob.exists?(job.id)
    end
  end

  def test_finish
    job = create_job(@printer)
    job.finish!(printed: true)
    assert_equal 'printed', job.reload.status
    assert_nil job.error

    job = create_job(@printer)
    job.finish!(printed: false, error: 'Error: No media')
    assert_equal 'failed', job.reload.status
    assert_equal 'Error: No media', job.error
  end

  def test_agent_json_has_the_label_and_its_lengths
    job = create_job(@printer, copies: 2)
    json = job.to_agent_json
    assert_equal %w[SMITH E1234], json[:lines]
    assert_equal 2, json[:copies]
    assert_equal 101.6, json[:max_length_mm]
    assert_equal 25.4, json[:min_length_mm]
  end
end
