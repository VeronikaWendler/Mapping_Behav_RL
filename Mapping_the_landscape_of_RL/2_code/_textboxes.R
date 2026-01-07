#' Plots text scaled by importance into a square area with horizontal alignment,
#' vertical centering, separators, and controllable line spacing.
#' Any overflowing text at the end is replaced with "..." (ellipsis).
#' The ellipsis font size matches the preceding text, and a single space is left before it.
#'
#' Attempts to fill the specified square area from top-left to bottom-right,
#' offset from the top by a specified whitespace margin.
#' Text font size is scaled by importance. Text wraps to the next line.
#' Full lines of text are aligned horizontally according to the `text_align` argument.
#' Lines ending with an ellipsis due to truncation are always left-aligned.
#' Text and separators on each line are vertically centered based on the tallest
#' element on that line.
#' A separator (vertically centered circle) is placed between each original text phrase
#' with equal horizontal padding on both sides, controlled by `separator_padding`.
#' Plotting stops when the bottom of the square is reached. If text overflows
#' vertically, the last piece of visible text will be truncated with an ellipsis ("...").
#'
#' Note: This function implements horizontal alignment line by line.
#' Precise vertical justification to fill the *entire* box perfectly is not
#' automatically achieved with arbitrary content and scaling in base R graphics.
#' The layout fills sequentially from the top (after the specified whitespace)
#' until vertical space runs out. If the amount of text is insufficient to fill
#' the available space with the chosen font scaling, the bottom of the box will
#' remain empty. If there is too much text, it will be truncated at the bottom,
#' with the ellipsis indicating truncation.
#' Text dimension calculations (`strwidth`, `strheight`) can sometimes be
#' device-dependent, which might affect precise wrapping and layout.
#'
#' @param texts A character vector of text strings (1 to 3 words each).
#' @param importances A numeric vector of importance values, corresponding to `texts`.
#' @param square_size A numeric vector `c(xmin, xmax, ymin, ymax)` defining the square area.
#' @param base_cex The base character expansion factor for the smallest importance. Used as a fallback for ellipsis CEX if no preceding text.
#' @param max_cex_addition The maximum additional character expansion factor for the highest importance.
#' @param separator_diameter The diameter of the circle used as a separator, in user coordinates.
#' @param separator_padding Equal horizontal space added on both sides of the separator circle, in user coordinates. This space contributes to the total horizontal space the separator element occupies in the layout.
#' @param separator_color The color of the separator circle.
#' @param text_align Horizontal alignment for full lines. Accepted values are "justified" and "left". The last line and lines ending with an ellipsis are always left-aligned.
#' @param top_whitespace A numeric value (0 to 1) representing the proportion of the square's height to reserve as whitespace at the top.
#' @param ellipsis_str The string to use for ellipsis when text overflows. Default is "...".
#' @param line_spacing_factor A numeric factor determining extra spacing between lines, relative to the line's content height.
#'        `0` (default) means no extra space (lines are packed based on their content height).
#'        `0.1` means 10% of the current line's content height is added as spacing below it.
#'        Must be non-negative.
#'
#' @examples
#' # Ensure a graphics device is open before running examples:
#' # if (interactive()) {
#' #   try(dev.off(), silent = TRUE) # Close any existing devices
#' #   if (.Platform$OS.type == "windows") windows() else if (Sys.info()["sysname"] == "Darwin") quartz() else X11()
#' #   plot.new() # Prepare the plot area
#' # } else {
#' #  # For non-interactive environments, you might need to set up a device like png()
#' #  # png("text_box_example.png"); plot.new() # Then run examples
#' # }
#'
#' # Example 1: With line spacing
#' # texts1 = c("Importance Scaling Justification", "Example Here with spacing", "More Text to Show")
#' # importances1 = c(5, 3, 4)
#' # text_box_new(texts1, importances1, separator_padding = 0.008, line_spacing_factor = 0.2)
#'
#' # Example 2: Overflowing text with line spacing
#' # if (interactive()) plot.new() 
#' # texts_overflow = c("This line visible.",
#' # "Second line also visible.",
#' # "Third line pushes content.",
#' # "Fourth line overflows.",
#' # "More text not seen.")
#' # importances_overflow = rep(5, 5)
#' # text_box_new(texts_overflow, importances_overflow,
#' #              square_size = c(0, 1, 0.5, 1), # Reduced vertical space
#' #              base_cex = 0.6, max_cex_addition = 0.2, top_whitespace = 0.05,
#' #              line_spacing_factor = 0.1)
#'
#' # if (!interactive()) dev.off() # Close file device if used
#'
#' @return NULL. Plots directly to the active graphics device.
text_box = function(texts, importances, square_size = c(0, 1, 0, 1),
                           base_cex = 0.5, max_cex_addition = 2.5,
                           separator_diameter = 0.02, separator_padding = 0.005,
                           separator_color = "black", text_align = "justified",
                           top_whitespace = 0, ellipsis_str = "...",
                           line_spacing_factor = 0) { # New parameter
  # --- Input Validation ---
  if (length(texts) != length(importances)) {
    stop("Text and importance vectors must have the same length.")
  }
  if (length(square_size) != 4) {
    stop("square_size must be a vector of 4: c(xmin, xmax, ymin, ymax).")
  }
  if (separator_padding < 0) {
    warning("separator_padding cannot be negative. Setting to 0.")
    separator_padding = 0
  }
  valid_alignments = c("justified", "left")
  if (!(text_align %in% valid_alignments)) {
    stop(paste("Invalid text_align value. Must be one of:", paste(valid_alignments, collapse = ", ")))
  }
  if (top_whitespace < 0 || top_whitespace > 1) {
    stop("top_whitespace must be a value between 0 and 1 (inclusive).")
  }
  if (line_spacing_factor < 0) { # Validation for new parameter
    warning("line_spacing_factor cannot be negative. Setting to 0.")
    line_spacing_factor = 0
  }
  
  
  # --- Normalize Importances ---
  sum_importances = sum(importances)
  if (sum_importances == 0 && length(importances) > 0) {
    warning("Sum of importances is zero. Using equal scaling for all texts.")
    normalized_importances = rep(1 / length(importances), length(importances))
  } else if (length(importances) == 0) {
    normalized_importances = numeric(0)
  } else {
    normalized_importances = importances / sum_importances
  }
  
  # --- Set up Plot Area ---
  plot(0, 0, type = "n", xlim = square_size[1:2], ylim = square_size[3:4],
       asp = 1, xlab = "", ylab = "", axes = FALSE)
  
  tryCatch({
    dummy_width = strwidth("M", cex = 1) 
    dummy_height = strheight("M", cex = 1)
  }, error = function(e) {
    warning("Graphics device might not be fully ready for text metrics: ", e$message)
  }, warning = function(w) {
    if (!grepl("RShowDoc", w$message) && !grepl("plot.new", w$message)) {
      warning("Warning during graphics device priming: ", w$message)
    }
  })
  
  if (length(texts) == 0) return(invisible(NULL))
  
  element_stream = list()
  for (i in seq_along(texts)) {
    words_in_text = unlist(strsplit(texts[i], "\\s+"))
    words_in_text = words_in_text[words_in_text != ""] 
    
    if(length(words_in_text) == 0 && i < length(texts)) {
      # Empty phrase, separator will still be added if not the last phrase.
    }
    
    num_words_in_text = length(words_in_text)
    
    for (j in seq_along(words_in_text)) {
      word = words_in_text[j]
      importance_val = normalized_importances[i]
      cex_value = base_cex + importance_val * max_cex_addition
      word_width = strwidth(word, cex = cex_value)
      estimated_height = strheight("Mg", cex = cex_value) * 1.1
      
      is_last_word_in_phrase = (j == num_words_in_text)
      is_followed_by_separator = (i < length(texts))
      
      space_after_element = if (is_last_word_in_phrase && is_followed_by_separator) {
        0 
      } else {
        strwidth(" ", cex = cex_value) 
      }
      
      element_stream = append(element_stream, list(list(type = "word",
                                                         word = word,
                                                         cex = cex_value,
                                                         width = word_width,
                                                         height = estimated_height,
                                                         space = space_after_element)))
    }
    
    if (i < length(texts)) {
      sep_layout_width = separator_diameter + 2 * separator_padding
      sep_height = separator_diameter 
      element_stream = append(element_stream, list(list(type = "separator",
                                                         width = sep_layout_width,
                                                         height = sep_height,
                                                         space = 0, 
                                                         sep_diameter = separator_diameter)))
    }
  }
  if (length(element_stream) == 0) return(invisible(NULL)) 
  
  plot_area_width = square_size[2] - square_size[1]
  square_height = square_size[4] - square_size[3]
  whitespace_height = square_height * top_whitespace
  current_y_top_of_line = square_size[4] - whitespace_height
  
  current_line_elements = list()
  current_line_layout_width = 0 
  current_line_max_height = 0
  
  ellipsis_added_globally = FALSE
  
  add_ellipsis_to_elements_list = function(line_els, avail_w, default_cex_val, el_str) {
    calculate_unjustified_width_loc = function(elements_list_loc) {
      if (length(elements_list_loc) == 0) return(0)
      total_w_loc = 0
      for (idx_loc in 1:length(elements_list_loc)) {
        total_w_loc = total_w_loc + elements_list_loc[[idx_loc]]$width
        if (idx_loc < length(elements_list_loc)) {
          total_w_loc = total_w_loc + elements_list_loc[[idx_loc]]$space
        }
      }
      return(total_w_loc)
    }
    
    for (num_keep in length(line_els):0) { 
      current_sub = if (num_keep > 0) line_els[1:num_keep] else list()
      if (length(current_sub) > 0 && current_sub[[length(current_sub)]]$type == "separator") {
        current_sub = current_sub[-length(current_sub)]
      }
      if (length(current_sub) == 0 && num_keep > 0) { next }
      
      final_ellipsis_cex = default_cex_val
      if (length(current_sub) > 0) {
        last_sub_el = current_sub[[length(current_sub)]]
        if (!is.null(last_sub_el$cex) && is.numeric(last_sub_el$cex)) {
          final_ellipsis_cex = last_sub_el$cex
        }
      }
      
      current_ellipsis_el = list(
        type = "word", word = el_str, cex = final_ellipsis_cex,
        width = strwidth(el_str, cex = final_ellipsis_cex),
        height = strheight(el_str, cex = final_ellipsis_cex) * 1.1, space = 0 
      )
      
      elements_to_test = list()
      if (length(current_sub) > 0) {
        current_sub_modified_for_space = current_sub 
        idx_last_el_in_sub = length(current_sub_modified_for_space)
        cex_for_space = default_cex_val 
        if(!is.null(current_sub_modified_for_space[[idx_last_el_in_sub]]$cex) && 
           is.numeric(current_sub_modified_for_space[[idx_last_el_in_sub]]$cex)) {
          cex_for_space = current_sub_modified_for_space[[idx_last_el_in_sub]]$cex
        }
        current_sub_modified_for_space[[idx_last_el_in_sub]]$space = strwidth(" ", cex = cex_for_space)
        elements_to_test = c(current_sub_modified_for_space, list(current_ellipsis_el))
      } else {
        elements_to_test = list(current_ellipsis_el)
      }
      
      prospective_width_val = calculate_unjustified_width_loc(elements_to_test)
      if (prospective_width_val <= avail_w) { return(elements_to_test) }
    } 
    return(list()) 
  }
  
  `%||%` = function(a, b) if (!is.null(a)) a else b
  
  plot_buffered_line = function(elements_info, y_top_of_line, max_h, plot_w, justify = TRUE) {
    if (length(elements_info) == 0 || max_h == 0) return(y_top_of_line) 
    
    line_center_y = y_top_of_line - (max_h / 2)
    total_elements_content_width = sum(sapply(elements_info, function(el) el$width))
    num_elements = length(elements_info)
    num_gaps = max(0, num_elements - 1)
    
    space_to_add_per_gap = 0
    is_single_word_line = num_elements == 1 && elements_info[[1]]$type == "word"
    
    if (justify && num_gaps > 0 && !is_single_word_line) { 
      remaining_h_space = plot_w - total_elements_content_width
      space_to_add_per_gap = max(0, remaining_h_space) / num_gaps
    }
    
    element_start_x_on_line = square_size[1] 
    for (k in seq_along(elements_info)) {
      el_info = elements_info[[k]]
      current_element_total_layout_span = el_info$width 
      
      if (el_info$type == "word") {
        text(element_start_x_on_line, line_center_y, labels = el_info$word,
             cex = el_info$cex, adj = c(0, 0.5)) 
        if (k < num_elements) { 
          if (justify && !is_single_word_line) {
            current_element_total_layout_span = current_element_total_layout_span + space_to_add_per_gap
          } else { 
            current_element_total_layout_span = current_element_total_layout_span + el_info$space
          }
        }
      } else if (el_info$type == "separator") {
        circle_center_x = element_start_x_on_line + el_info$width / 2 
        radius_user = el_info$sep_diameter / 2
        symbols(x = circle_center_x, y = line_center_y, circles = radius_user,
                inches = FALSE, add = TRUE, fg = separator_color, bg = separator_color)
        if (k < num_elements) { 
          if (justify && !is_single_word_line) {
            current_element_total_layout_span = current_element_total_layout_span + space_to_add_per_gap
          } 
        }
      }
      element_start_x_on_line = element_start_x_on_line + current_element_total_layout_span
    }
    # This function's responsibility is plotting. Y-update with line spacing happens in the caller.
    return(y_top_of_line) # Caller will subtract total span from this
  }
  
  # --- Main Loop over Element Stream ---
  for (stream_idx in seq_along(element_stream)) {
    current_element = element_stream[[stream_idx]]
    is_last_element_in_stream = (stream_idx == length(element_stream))
    
    potential_new_line_width = current_line_layout_width + current_element$width + current_element$space
    
    if (potential_new_line_width > plot_area_width && length(current_line_elements) > 0) {
      # --- Process full line (current_line_elements) ---
      current_line_content_h = current_line_max_height 
      justify_this_line_flag = (text_align == "justified")
      
      current_line_total_span = current_line_content_h * (1 + line_spacing_factor)
      if (current_line_content_h == 0) current_line_total_span = 0
      
      if (current_line_content_h > 0 && (current_y_top_of_line - current_line_total_span < square_size[3])) {
        if (!ellipsis_added_globally) {
          warning(paste0("Line (starting '", (current_line_elements[[1]]$word %||% "element"),
                         "') plus its line spacing overflows. Not plotted."))
        }
        ellipsis_added_globally = TRUE 
        break 
      }
      
      elements_to_plot = current_line_elements 
      max_h_to_plot = current_line_content_h    
      
      y_where_next_line_content_starts = current_y_top_of_line - current_line_total_span 
      min_next_content_h = current_element$height 
      
      if (min_next_content_h > 0 && (y_where_next_line_content_starts - min_next_content_h < square_size[3])) {
        if (!ellipsis_added_globally) {
          warning(paste0("Text starting with '", current_element$word %||% "separator", "' would overflow. Adding ellipsis to current line."))
          elements_to_plot = add_ellipsis_to_elements_list(current_line_elements, plot_area_width, base_cex, ellipsis_str)
          if (length(elements_to_plot) > 0) {
            max_h_to_plot = max(sapply(elements_to_plot, function(el) el$height))
          } else { 
            max_h_to_plot = 0 
          }
          ellipsis_added_globally = TRUE
          justify_this_line_flag = FALSE; 
        }
      }
      
      final_content_h_for_plot = max_h_to_plot
      final_total_span_for_plot = final_content_h_for_plot * (1 + line_spacing_factor)
      if (final_content_h_for_plot == 0) final_total_span_for_plot = 0
      
      if (final_content_h_for_plot > 0) {
        if (current_y_top_of_line - final_total_span_for_plot < square_size[3]) {
          if(!ellipsis_added_globally) { 
            warning("Line (even after potential ellipsis) plus its spacing still too tall. Not plotted.")
          }
          ellipsis_added_globally = TRUE 
        } else {
          plot_buffered_line(elements_to_plot, current_y_top_of_line, final_content_h_for_plot, plot_area_width, justify = justify_this_line_flag)
          current_y_top_of_line = current_y_top_of_line - final_total_span_for_plot 
        }
      } else if (ellipsis_added_globally && length(current_line_elements) > 0 && final_content_h_for_plot == 0) {
        warning("Ellipsis version of a line was empty or had zero height; line effectively skipped.")
      }
      
      if (ellipsis_added_globally) break 
      
      current_line_elements = list(current_element)
      current_line_layout_width = current_element$width + current_element$space
      current_line_max_height = current_element$height
      
    } else { 
      current_line_elements = append(current_line_elements, list(current_element))
      current_line_layout_width = potential_new_line_width 
      current_line_max_height = max(current_line_max_height, current_element$height)
    }
    
    if (is_last_element_in_stream) {
      # --- Process final line (current_line_elements) ---
      if (length(current_line_elements) > 0 && !ellipsis_added_globally) {
        final_line_content_h = current_line_max_height
        elements_for_final_line = current_line_elements # Default to current buffer
        
        final_line_total_span_pre_ellipsis = final_line_content_h * (1 + line_spacing_factor)
        if(final_line_content_h == 0) final_line_total_span_pre_ellipsis = 0
        
        if (final_line_content_h > 0 && (current_y_top_of_line - final_line_total_span_pre_ellipsis < square_size[3])) {
          warning("Final line of text (plus its spacing) overflows. Adding ellipsis.")
          elements_for_final_line = add_ellipsis_to_elements_list(current_line_elements, plot_area_width, base_cex, ellipsis_str)
          if (length(elements_for_final_line) > 0) {
            final_line_content_h = max(sapply(elements_for_final_line, function(el) el$height))
          } else { 
            final_line_content_h = 0 
          }
          ellipsis_added_globally = TRUE 
        }
        
        # Recalculate total span with potentially modified elements/height
        final_line_total_span_post_ellipsis = final_line_content_h * (1 + line_spacing_factor)
        if(final_line_content_h == 0) final_line_total_span_post_ellipsis = 0
        
        if (final_line_content_h > 0) {
          if (current_y_top_of_line - final_line_total_span_post_ellipsis >= square_size[3]) { 
            plot_buffered_line(elements_for_final_line, current_y_top_of_line, final_line_content_h, plot_area_width, justify = FALSE) 
            current_y_top_of_line = current_y_top_of_line - final_line_total_span_post_ellipsis
          } else {
            warning("Even ellipsis version of the final line (plus spacing) does not fit. Not plotted.")
          }
        } else if (length(current_line_elements) > 0 && ellipsis_added_globally && final_line_content_h == 0) {
          warning("Ellipsis version of the final line was empty or zero height; line skipped.")
        }
      }
      break 
    }
    if (ellipsis_added_globally) break 
  } 
  
  invisible(NULL)
}