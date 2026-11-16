#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Administration » Label printers: the printers (one print agent each), their agents' tokens and status, and
# the labels printed lately
class LabelPrintersController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :label_printers

  before_action :require_admin
  before_action :find_printer, only: [:edit, :update, :destroy, :regenerate_token]

  def index
    @printers = LabelPrinter.sorted.to_a
    LabelJob.expire_lapsed
    @jobs = LabelJob.recent.includes(:label_printer, :user).limit(50)
  end

  def new
    @printer = LabelPrinter.new
  end

  def create
    @printer = LabelPrinter.new(printer_params)
    @printer.generate_token
    if @printer.save
      render_token
    else
      render action: 'new'
    end
  end

  def edit; end

  def update
    if @printer.update(printer_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to label_printers_path
    else
      render action: 'edit'
    end
  end

  # A new token for the printer's agent; the old one stops working right away
  def regenerate_token
    @printer.generate_token
    @printer.save!
    render_token
  end

  def destroy
    @printer.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to label_printers_path
  end

  private

  def find_printer
    @printer = LabelPrinter.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def printer_params
    params.require(:label_printer).permit(:name, :active)
  end

  # The token is only ever shown here, right after it's made
  def render_token
    response.headers['Cache-Control'] = 'no-store'
    render action: 'token'
  end
end
