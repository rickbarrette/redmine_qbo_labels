#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# The Print label dialog: opened from an issue, estimate, invoice, customer or appointment, or blank from the
# sidebar (new), sends the label to a printer's
# queue (create), and follows it until it's printed (show, polled by the dialog). The dialog asks for show's
# JSON with an Accept header, not a .json URL: Redmine treats .json as the REST API, without the session.
class LabelJobsController < ApplicationController
  before_action :authorize_global
  before_action :find_source, only: [:new, :create]
  before_action :find_printers, only: [:new, :create]

  def new
    @lines = @source.lines
    @copies = 1
    respond_to { |format| format.js }
  end

  def create
    @lines = Array(params[:lines]).first(LabelJob::MAX_LINES)
    @copies = params[:copies].to_i.clamp(1, LabelJob::MAX_COPIES)
    printer = @printers.find { |p| p.id == params[:printer_id].to_i } || @printers.first
    @job = LabelJob.new(label_printer: printer, user: User.current, lines: @lines, copies: @copies,
                        source_type: @source.type, source_id: @source.id&.to_s)
    @job.save if printer
    respond_to { |format| format.js }
  end

  def show
    @job = LabelJob.find_by(id: params[:id])
    return render_404 unless @job && (@job.user_id == User.current.id || User.current.admin?)

    LabelJob.expire_lapsed unless @job.finished?
    @job.reload
    respond_to do |format|
      format.json do
        render json: { id: @job.id, status: @job.status, status_label: @job.status_label, error: @job.error,
                       finished: @job.finished?, printer_online: @job.label_printer.online? }
      end
    end
  end

  private

  def find_source
    @source = RedmineQboLabels::LabelSource.find(params[:source_type], params[:source_id])
    render_404 unless @source
  end

  def find_printers
    @printers = LabelPrinter.active.sorted.to_a
  end
end
