#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# A label sent to a label printer. Queued until the printer's agent picks it up (printing), then printed or
# failed; one its agent never picks up expires (RedmineQboLabels::Settings.job_expiry), so a label doesn't
# print long after it was asked for.
class LabelJob < ApplicationRecord
  STATUSES = %w[queued printing printed failed expired].freeze
  FINISHED = %w[printed failed expired].freeze
  MAX_LINES = 4
  MAX_LINE_LENGTH = 40
  MAX_COPIES = 10
  # A label the agent took but never reported on
  PRINTING_TIMEOUT = 2.minutes
  # Finished jobs are kept this long
  KEEP_FOR = 30.days

  belongs_to :label_printer
  belongs_to :user, optional: true

  serialize :lines, coder: JSON, type: Array

  validates :status, inclusion: { in: STATUSES }
  validates :copies, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_COPIES }
  validate :validate_lines

  before_validation :normalize_lines, on: :create

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def finished?
    FINISHED.include?(status)
  end

  # The next queued label for a printer, marked as printing, or nil. Lapsed jobs are expired first.
  def self.claim_next(printer)
    expire_lapsed
    transaction do
      job = printer.label_jobs.where(status: 'queued').order(:id).lock.first
      job&.update!(status: 'printing', claimed_at: Time.current)
      job
    end
  end

  # Queued jobs past their expiry, and printing jobs the agent never reported on; old finished jobs go
  def self.expire_lapsed
    now = Time.current
    where(status: 'queued').where(created_at: ...RedmineQboLabels::Settings.job_expiry.ago)
      .update_all(status: 'expired', finished_at: now, updated_at: now,
                  error: I18n.t(:text_qbo_labels_job_expired))
    where(status: 'printing').where(claimed_at: ...PRINTING_TIMEOUT.ago)
      .update_all(status: 'failed', finished_at: now, updated_at: now,
                  error: I18n.t(:text_qbo_labels_job_unconfirmed))
    where(created_at: ...KEEP_FOR.ago).delete_all
  end

  # The agent's report: printed, or failed with why
  def finish!(printed:, error: nil)
    update!(status: printed ? 'printed' : 'failed', finished_at: Time.current,
            error: printed ? nil : error.to_s.truncate(1000).presence || I18n.t(:text_qbo_labels_job_failed))
  end

  # What the agent needs to print it
  def to_agent_json
    {
      id: id, lines: lines, copies: copies,
      max_length_mm: RedmineQboLabels::Settings.max_length_mm,
      min_length_mm: RedmineQboLabels::Settings.min_length_mm
    }
  end

  def status_label
    I18n.t("label_qbo_labels_status_#{status}")
  end

  def source
    RedmineQboLabels::LabelSource.find(source_type, source_id) if source_type.present?
  end

  private

  def normalize_lines
    self.lines = Array(lines).map { |line| line.to_s.squish }
    self.lines = lines.map(&:upcase) if RedmineQboLabels::Settings.uppercase?
    self.lines = lines.reject(&:blank?)
  end

  def validate_lines
    if lines.blank?
      errors.add(:base, :qbo_labels_no_text)
    elsif lines.size > MAX_LINES || lines.any? { |line| line.length > MAX_LINE_LENGTH }
      errors.add(:base, :qbo_labels_text_too_long, count: MAX_LINE_LENGTH)
    end
  end
end
