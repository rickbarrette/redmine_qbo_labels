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

class LabelPrinterTest < ActiveSupport::TestCase
  include QboLabelsTestHelper

  def test_token_signs_the_agent_in_and_only_its_digest_is_kept
    printer, token = create_printer
    assert token.start_with?('qbl_')
    assert_not_equal token, printer.reload.token_digest
    assert_equal printer, LabelPrinter.authenticate(token)
    assert_nil LabelPrinter.authenticate('qbl_wrong')
    assert_nil LabelPrinter.authenticate('')
  end

  def test_inactive_printers_cannot_sign_in
    printer, token = create_printer(active: false)
    assert_nil LabelPrinter.authenticate(token)
    printer.update!(active: true)
    assert_equal printer, LabelPrinter.authenticate(token)
  end

  def test_new_token_replaces_the_old_one
    printer, token = create_printer
    new_token = printer.generate_token
    printer.save!
    assert_nil LabelPrinter.authenticate(token)
    assert_equal printer, LabelPrinter.authenticate(new_token)
  end

  def test_seen_records_the_agent_and_its_printer
    printer, = create_printer
    assert_not printer.online?
    printer.seen!(ip: '10.0.0.5', agent: { 'version' => '2026.11.0', 'printer_model' => 'QL-820NWB',
                                           'printer_address' => '192.168.0.100:9100',
                                           'printer_status' => 'Ready, 62mm continuous' })
    printer.reload
    assert printer.online?
    assert_equal '10.0.0.5', printer.last_ip
    assert_equal 'QL-820NWB', printer.printer_model
    assert_equal '192.168.0.100:9100', printer.printer_address
    assert_equal 'Ready, 62mm continuous', printer.printer_status
  end

  def test_seen_writes_last_seen_only_every_few_seconds
    printer, = create_printer
    printer.seen!(ip: '10.0.0.5')
    first = printer.reload.last_seen_at
    travel 5.seconds do
      printer.seen!(ip: '10.0.0.5')
      assert_equal first, printer.reload.last_seen_at
    end
    travel 20.seconds do
      printer.seen!(ip: '10.0.0.5')
      assert_operator printer.reload.last_seen_at, :>, first
    end
  end

  def test_names_are_unique
    create_printer(name: 'Parts room')
    printer = LabelPrinter.new(name: 'parts ROOM')
    printer.generate_token
    assert_not printer.valid?
  end
end
