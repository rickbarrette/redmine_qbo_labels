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

class LabelPrintersTest < Redmine::IntegrationTest
  include QboLabelsTestHelper
  fixtures :users, :email_addresses

  def test_admins_add_a_printer_and_see_its_token_once
    log_user('admin', 'admin')
    get '/label_printers'
    assert_response :success

    assert_difference 'LabelPrinter.count', 1 do
      post '/label_printers', params: { label_printer: { name: 'Parts room', active: '1' } }
    end
    assert_response :success
    token = css_select('pre.qbo-label-token').first.text.strip
    assert LabelPrinter.authenticate(token)
    assert_includes response.body, 'AGENT_TOKEN'
    assert_equal 'no-store', response.headers['Cache-Control']

    get '/label_printers'
    assert_not_includes response.body, token
  end

  def test_new_token
    printer, token = create_printer
    log_user('admin', 'admin')
    post "/label_printers/#{printer.id}/regenerate_token"
    assert_response :success
    assert_nil LabelPrinter.authenticate(token)
  end

  def test_admins_only
    log_user('jsmith', 'jsmith')
    get '/label_printers'
    assert_response :forbidden
  end
end
