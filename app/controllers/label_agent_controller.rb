#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# The print agent's API (redmine-qbo-label-agent). The agent runs on the printer's network, so Redmine never
# needs to reach the printer: the agent signs in with its printer's token (Authorization: Bearer <token>),
# asks for the next label every couple of seconds, prints it, and reports back.
#
#   POST /label_agent/poll              { "agent": { "version", "printer_model", "printer_address",
#                                                     "printer_status" } }  (agent is optional)
#     => { "job": { "id", "lines", "copies", "max_length_mm", "min_length_mm" } | null, "poll_seconds" }
#   POST /label_agent/jobs/:id/result   { "status": "printed" | "failed", "error": "..." }
#     => { "ok": true }
class LabelAgentController < ActionController::API
  before_action :authenticate_agent

  def poll
    @printer.seen!(ip: request.remote_ip, agent: agent_params)
    job = LabelJob.claim_next(@printer)
    log_request(job ? "sent job #{job.id}" : 'no job')
    render json: { job: job&.to_agent_json, poll_seconds: RedmineQboLabels::Settings.poll_seconds }
  end

  def result
    job = @printer.label_jobs.find_by(id: params[:id])
    return render(json: { error: 'not found' }, status: :not_found) unless job

    # A repeated report (the agent retrying after a dropped connection) changes nothing
    job.finish!(printed: params[:status] == 'printed', error: params[:error]) unless job.finished?
    log_request("job #{job.id} #{job.status}#{" (#{job.error})" if job.error.present?}")
    render json: { ok: true, status: job.status }
  end

  private

  def authenticate_agent
    token = request.authorization.to_s[/\ABearer\s+(\S+)\z/, 1]
    @printer = LabelPrinter.authenticate(token)
    return if @printer

    Rails.logger.warn "[redmine_qbo_labels] Print agent from #{request.remote_ip} has an unknown token"
    render json: { error: 'unauthorized' }, status: :unauthorized
  end

  def agent_params
    agent = params[:agent]
    agent.respond_to?(:permit) ? agent.permit(:version, :printer_model, :printer_address, :printer_status).to_h : nil
  end

  def log_request(message)
    return unless RedmineQboLabels::Settings.log_requests?

    Rails.logger.info "[redmine_qbo_labels] #{@printer.name} agent (#{request.remote_ip}): #{message}"
  end
end
