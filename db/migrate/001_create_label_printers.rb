#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class CreateLabelPrinters < ActiveRecord::Migration[7.0]
  def change
    # A label printer and the print agent on its network that prints its labels
    create_table :label_printers do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      # SHA-256 of the agent's token (the token itself is only shown once)
      t.string :token_digest, null: false
      # What the agent last reported
      t.datetime :last_seen_at
      t.string :last_ip
      t.string :agent_version
      t.string :printer_model
      t.string :printer_address
      t.string :printer_status
      t.timestamps
    end
    add_index :label_printers, :token_digest, unique: true
  end
end
