#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# A label printer, reached through the print agent on its network. The agent signs in with a token and asks
# for labels every couple of seconds (LabelAgentController).
class LabelPrinter < ApplicationRecord
  TOKEN_PREFIX = 'qbl_'
  # The agent counts as online when it asked for labels within this time
  ONLINE_WITHIN = 30.seconds
  # How often an agent's polls update last_seen_at (saves a write every 2 seconds)
  SEEN_RESOLUTION = 15.seconds

  has_many :label_jobs, dependent: :delete_all

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { case_sensitive: false }
  validates :token_digest, presence: true

  scope :active, -> { where(active: true) }
  scope :sorted, -> { order(:name) }

  attr_reader :token

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  # The active printer whose agent has this token, or nil
  def self.authenticate(token)
    return nil unless token.to_s.start_with?(TOKEN_PREFIX)

    active.find_by(token_digest: digest(token))
  end

  # Makes a new token (kept in #token until the record is reloaded) and returns it
  def generate_token
    @token = "#{TOKEN_PREFIX}#{SecureRandom.base58(32)}"
    self.token_digest = self.class.digest(@token)
    @token
  end

  def online?
    last_seen_at.present? && last_seen_at > ONLINE_WITHIN.ago
  end

  # Records an agent's poll, and what it says about the printer when it says anything
  def seen!(ip:, agent: nil)
    changes = {}
    changes[:last_seen_at] = Time.current if last_seen_at.nil? || last_seen_at < SEEN_RESOLUTION.ago
    changes[:last_ip] = ip if ip.present? && ip != last_ip
    if agent.is_a?(Hash)
      { agent_version: 'version', printer_model: 'printer_model', printer_address: 'printer_address',
        printer_status: 'printer_status' }.each do |column, key|
        next unless agent.key?(key)

        value = agent[key].to_s.truncate(250).presence
        changes[column] = value if value != self[column]
      end
    end
    update_columns(changes.merge(updated_at: Time.current)) if changes.any?
  end

  def to_s
    name
  end
end
