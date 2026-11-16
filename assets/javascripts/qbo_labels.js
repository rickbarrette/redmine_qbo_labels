/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2026 rick barrette
 *
 * Print label dialog (redmine_qbo_labels): draws a preview of the label the way the print agent draws it,
 * then follows the print job until it's printed.
 *
 * Label layout (keep in step with the agent's label.py): the label runs along a 62mm continuous roll at
 * 300 dpi, so it's 696 dots tall and as long as its text needs, between the minimum and maximum length.
 * The lines are stacked, left aligned, each in the largest bold letters that fit.
 */
var QboLabels = (function($) {
  'use strict';

  var LAYOUT = {
    dpi: 300,
    height: 696,      // printable dots across a 62mm roll
    marginX: 36,      // ~3mm at each end
    marginY: 24,      // ~2mm top and bottom
    gapRatio: 0.12,   // space between lines, as a share of the (smallest) font size
    minSize: 8,
    maxSize: 700,
    sameSizeWithin: 1.25, // lines whose biggest sizes are this close are drawn the same size
    font: 'QboLabel'
  };

  var pollTimer = null;
  var following = null;

  function mmToDots(mm) {
    return Math.round(mm / 25.4 * LAYOUT.dpi);
  }

  function fontAt(size) {
    return '700 ' + size + 'px ' + LAYOUT.font + ', "DejaVu Sans", Arial, sans-serif';
  }

  // A line's ink at a font size: { left, right, ascent, descent, width, height }
  function box(ctx, text, size) {
    ctx.font = fontAt(size);
    var m = ctx.measureText(text);
    var left = m.actualBoundingBoxLeft || 0, right = m.actualBoundingBoxRight || m.width;
    var ascent = m.actualBoundingBoxAscent || size * 0.73, descent = m.actualBoundingBoxDescent || 0;
    return { left: left, right: right, ascent: ascent, descent: descent,
             width: left + right, height: ascent + descent };
  }

  // The largest font size from minSize to maxSize that passes the test (minSize if none does)
  function largest(test) {
    var lo = LAYOUT.minSize, hi = LAYOUT.maxSize;
    while (lo < hi) {
      var mid = Math.floor((lo + hi + 1) / 2);
      if (test(mid)) { lo = mid; } else { hi = mid - 1; }
    }
    return lo;
  }

  function gapFor(sizes) {
    return Math.round(Math.min.apply(null, sizes) * LAYOUT.gapRatio);
  }

  function totalHeight(ctx, lines, sizes) {
    return lines.reduce(function(sum, text, i) { return sum + box(ctx, text, sizes[i]).height; }, 0) +
      gapFor(sizes) * (lines.length - 1);
  }

  // Each line's font size and box, and the label's length in dots. Every line is as big as it can be: no
  // wider than the longest label allows, and together no taller than the roll. Lines that would come out
  // about the same size are made the same size; when one is held back by its length (a long name), the
  // others still grow to fill the height.
  function layout(ctx, lines, minLengthMm, maxLengthMm) {
    var maxLength = mmToDots(maxLengthMm), minLength = mmToDots(minLengthMm);
    var maxWidth = maxLength - 2 * LAYOUT.marginX, maxHeight = LAYOUT.height - 2 * LAYOUT.marginY;

    var limits = lines.map(function(text) {
      return largest(function(size) {
        var b = box(ctx, text, size);
        return b.width <= maxWidth && b.height <= maxHeight;
      });
    });
    function sizesAt(cap) { return limits.map(function(limit) { return Math.min(cap, limit); }); }

    var cap = largest(function(c) { return totalHeight(ctx, lines, sizesAt(c)) <= maxHeight; });
    var sizes = sizesAt(cap);
    var smallest = Math.min.apply(null, sizes);
    if (Math.max.apply(null, sizes) < smallest * LAYOUT.sameSizeWithin) {
      sizes = sizes.map(function() { return smallest; });
    }

    var boxes = lines.map(function(text, i) { return box(ctx, text, sizes[i]); });
    var width = Math.max.apply(null, boxes.map(function(b) { return b.width; }));
    var length = Math.min(maxLength, Math.max(minLength, Math.ceil(width + 2 * LAYOUT.marginX)));
    return { sizes: sizes, boxes: boxes, length: length };
  }

  function draw(canvas, lines, opts) {
    var ctx = canvas.getContext('2d');
    if (!lines.length) {
      canvas.width = mmToDots(opts.minLengthMm); canvas.height = LAYOUT.height;
      ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, canvas.width, canvas.height);
      return null;
    }
    var result = layout(ctx, lines, opts.minLengthMm, opts.maxLengthMm);
    canvas.width = result.length;
    canvas.height = LAYOUT.height;
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#000';
    ctx.textBaseline = 'alphabetic';

    var gap = gapFor(result.sizes);
    var total = result.boxes.reduce(function(sum, b) { return sum + b.height; }, 0) + gap * (lines.length - 1);
    var y = Math.round((LAYOUT.height - total) / 2);
    lines.forEach(function(text, i) {
      var b = result.boxes[i];
      ctx.font = fontAt(result.sizes[i]);
      ctx.fillText(text, LAYOUT.marginX + b.left, y + b.ascent);
      y += b.height + gap;
    });
    return result;
  }

  function dialog() { return $('#qbo-label-dialog'); }

  function currentLines($dialog) {
    var upper = $dialog.data('uppercase') === true || $dialog.data('uppercase') === 'true';
    return $dialog.find('.qbo-label-line').map(function() {
      var text = $.trim($(this).val()).replace(/\s+/g, ' ');
      return upper ? text.toUpperCase() : text;
    }).get().filter(function(text) { return text.length > 0; });
  }

  function redraw() {
    var $dialog = dialog();
    var canvas = $dialog.find('canvas.qbo-label-preview')[0];
    if (!canvas) { return; }
    var lines = currentLines($dialog);
    var result = draw(canvas, lines, {
      minLengthMm: parseFloat($dialog.data('min-length-mm')),
      maxLengthMm: parseFloat($dialog.data('max-length-mm'))
    });
    var inches = (canvas.width / LAYOUT.dpi).toFixed(1);
    $dialog.find('.qbo-label-size').text(result ? '2.4 × ' + inches + ' in' : '');
    $dialog.find('.qbo-label-submit').prop('disabled', !result);
  }

  function initDialog() {
    var $dialog = dialog();
    stopFollowing();
    $dialog.on('input change', '.qbo-label-line', redraw);
    redraw();
    // Redraw once the label font has loaded (the first draw may use a fallback font)
    if (document.fonts && document.fonts.load) {
      document.fonts.load(fontAt(100), 'A').then(function() { redraw(); }, function() {});
    }
    $dialog.find('.qbo-label-line').first().trigger('focus');
    // Stop following the job when the dialog is closed
    $('#ajax-modal').off('dialogclose.qboLabels').on('dialogclose.qboLabels', stopFollowing);
  }

  function setStatus(text, state) {
    var $status = dialog().find('.qbo-label-status');
    $status.prop('hidden', false).attr('data-state', state || 'working');
    $status.find('.qbo-label-status-text').text(text);
    $status.find('.qbo-label-again').toggle(state === 'printed' || state === 'failed');
  }

  function stopFollowing() {
    if (pollTimer) { clearTimeout(pollTimer); }
    pollTimer = null;
    following = null;
  }

  // Follows a print job until it's printed, failed or expired
  function follow(job) {
    var $dialog = dialog();
    stopFollowing();
    following = { url: job.url, errors: 0 };
    // .hide(): Redmine's styles show forms whatever their hidden attribute says
    $dialog.find('#qbo-label-form').hide();
    setStatus(job.printer_online ? $dialog.data('text-printing') : $dialog.data('text-offline'));
    poll(following);
  }

  function poll(state) {
    if (following !== state) { return; }
    $.ajax({ url: state.url, dataType: 'json', cache: false }).done(function(data) {
      if (following !== state) { return; }
      state.errors = 0;
      if (data.finished) {
        var text = data.status_label + (data.error ? ': ' + data.error : '');
        setStatus(text, data.status === 'printed' ? 'printed' : 'failed');
        stopFollowing();
        return;
      }
      var $dialog = dialog();
      if (data.status === 'printing') {
        setStatus($dialog.data('text-printing'));
      } else {
        setStatus(data.printer_online ? $dialog.data('text-waiting') : $dialog.data('text-offline'));
      }
      pollTimer = setTimeout(function() { poll(state); }, 1000);
    }).fail(function() {
      if (following !== state) { return; }
      state.errors += 1;
      if (state.errors >= 5) {
        setStatus(dialog().data('text-lost'), 'failed');
        stopFollowing();
      } else {
        pollTimer = setTimeout(function() { poll(state); }, 2000);
      }
    });
  }

  // Back to the form, to print the label again or another one
  function again() {
    var $dialog = dialog();
    stopFollowing();
    $dialog.find('.qbo-label-status').prop('hidden', true);
    $dialog.find('#qbo-label-form').show().find('.qbo-label-submit').prop('disabled', false);
    redraw();
  }

  // Moves the issue's Print label link into its top-right actions, before the "..." menu
  function placeIssueLink(selector) {
    var template = $(selector)[0];
    if (!template) { return; }
    var $menu = $('#content > .contextual').not('.next-prev-links').first();
    if (!$menu.length) { return; }
    var $link = $(document.importNode(template.content, true));
    var $drdn = $menu.children('.drdn');
    if ($drdn.length) { $drdn.first().before($link); } else { $menu.append($link); }
  }

  return { initDialog: initDialog, follow: follow, again: again, placeIssueLink: placeIssueLink,
           layout: layout, LAYOUT: LAYOUT };
})(jQuery);
