#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class CreateLabelJobs < ActiveRecord::Migration[7.0]
  def change
    # A label sent to a printer: queued until its agent picks it up, then printed or failed
    create_table :label_jobs do |t|
      t.references :label_printer, null: false
      t.references :user
      t.text :lines, null: false
      t.integer :copies, null: false, default: 1
      t.string :status, null: false, default: 'queued'
      t.text :error
      # The issue, estimate or invoice it's for
      t.string :source_type
      t.string :source_id
      t.datetime :claimed_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :label_jobs, [:label_printer_id, :status]
    add_index :label_jobs, :created_at
  end
end
