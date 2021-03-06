
# Instructions -------------------------------------------------------
mod_UI_maps_instructions <- function(id, specific) {
  ns <- NS(id)
  tagList(
    h3("Instructions:", actionButton(ns("help_instructions"), "?", class = "help"))
  )
}

mod_maps_instructions <- function(input, output, session) {

  ns <- session$ns

  observeEvent(input$help_instructions, {
    showModal(modalDialog(size = "l",
                          title = "Animations",
                          easyClose = TRUE,
    tagList(
      h4("General Instructions"),
      p("Events can be animated over time by clicking on the", strong("small blue arrow"), "to the lower right of the 'Time' slider (right)."),
      p("The time interval (resolution) and the speed of the animation can be adjusted below."),
      hr(),

      h4("Summary over time"),
      tags$ul(
        tags$li("Cumulative: All data up to and including a particular time block"),
        tags$li("Instantaneous: Data only in a particular time block")),

      h4("Select Individual"),
      tags$ul(
        tags$li("All: Summarize over all indivdiuals"),
        tags$li("Choose the specific individual"),
        tags$li("(X mv; Y fd) represent total number of times present at and movements between loggers respectively.")),

      h4("Summary Type"),
      tags$ul(tags$li("What kind of summary should be shown"),
              tags$ul(tags$li("Total sum: Sum of all time present and sum of all movements over time (cumulative) or within a particular time block (instantaneous)"),
                      tags$li("Average sum: Average per individual of sum of all time present and of all movements over time (cumulative) or within a particular time block (instanteneous)"))),

      h4("Time Range"),
      tags$ul(tags$li("Select the particular time range to use"),
              tags$li("The plot under the map shows events over time within this time range")),

      h4("Resolution"),
      tags$ul(tags$li("Data is summarized within blocks of time, this is the resolution of those blocks."),
              tags$li("Also the 'frame' of the animtions")),

      h4("Animation Speed"),
      tags$ul(tags$li("Speed of the animation")),

      h4("Show sunrise/sunset"),
      tags$ul(tags$li("Show a shawdow overlay on the map during nighttime hours")),

       h4("Map"),
      tags$ul(tags$li("Circles show the amount of activity at each logger for the given time interval."))
    )))

  })

}

# Tips -------------------------------------------------------
mod_UI_maps_tips <- function(id, specific) {
  ns <- NS(id)
  tagList(
    h3("Tips:"),
    p("To prevent animations from lagging, the resolution you can animate over is limited. To animate over a smaller resolution, reduce the time range."),
    p("The time depicted in the slider bar to the left indicates the middle of the time interval over which you are animating. For example, if you pick a resolution of 1 hr and the time shows 2016-01-07 09:30:00, the data has been summarized over 1 hour from 9am until 10am.")
  )
}


# Animation Controls -------------------------------------------------------
#' @import shiny
mod_UI_maps_controls <- function(id) {
  # Create a namespace function using the provided id
  ns <- NS(id)
  tagList(
    uiOutput(ns("UI_time_range")),
    hr(),
    h4("Animation options"),
    uiOutput(ns("UI_interval")),
    sliderInput(ns("anim_speed"), "Animation speed",
                       min = 0, max = 100,
                       post = "%",
                       value = 50)
  )
}

# Module server function
#' @import shiny
mod_maps_controls <- function(input, output, session, times, debounce_int, verbose = FALSE) {

  ns <- session$ns

  t <- reactive({
    req(times())
    if(verbose) cat("  Times - Setup\n")
    x <- tz_offset(tz = attr(times(), "tzone"))
    if(x >= 0) x <- paste0("+", sprintf("%02d", abs(x)), "00") else x <- paste0("-", sprintf("%02d", abs(x)), "00")

    list("times" = times(),
         "start" = lubridate::floor_date(min(times()), unit = "day"),
         "end" = lubridate::ceiling_date(max(times()), unit = "day"),
         "tz" = lubridate::tz(times()),
         "tz_offset" = x)
    })

  # Time range - select subsection of data
  output$UI_time_range <- renderUI({
    if(verbose) cat("  UI - Time range\n")
    x <- difftime(t()$end, t()$start)
    if(units(x) == "hours" | (units(x) == "days" && x <= 7)) s <- 60*60
    if(units(x) == "days" && x > 7) s <- 60*60*24

    sliderInput(ns("time_range"), "Time Range",
                min = t()$start,
                max = t()$end,
                value = c(t()$start, t()$end),
                step = s,
                timezone = t()$tz_offset,
                width = '100%')
  })

  ## UI Interval
  output$UI_interval <- renderUI({
    if(verbose) cat("  UI - Interval\n")
    radioButtons(ns("interval"), "Resolution",
                 choices = data_limits()$i,
                 selected = interval_selection(c(min(t()$times), max(t()$times))), inline = TRUE)
  })

  interval_d <- debounce(reactive({
    req(input$interval)
    if(verbose) cat("  Input - Interval\n")
    as.numeric(input$interval)
  }), debounce_int)

  interval <- reactive({
    if(ready(interval_d())) return(interval_d()) else return(as.vector(last(data_limits()$i)))
  })

  # Update Interval
  observe({
    req(input$interval)
    i <- data_limits()

    ## Toggle radio buttons
    lapply(1:(length(i$i)-1), function(a) shinyjs::toggleState(selector = paste0("input[type='radio'][value='", i$i[a], "']"), condition = data_range() < i$n[a+1]))

    ## Adjust selection
    s <- interval_selection(data_range(), i)
    if(s > as.numeric(interval())) updateRadioButtons(session, "interval", selected = s)
  })

  ## Floor/ceiling to nearest relevant hour. For larger time periods, start at 6am
  time_range_d <- debounce(reactive({
    req(input$time_range)
    req(lubridate::interval(input$time_range[1], input$time_range[2]) %within% lubridate::interval(t()$start, t()$end))

    tr <- lubridate::with_tz(input$time_range, t()$tz)
    i <- interval()

    isolate({
      if(verbose) cat("  Input - Time range\n")
      if(i <= 60) {
        tr[1] <- lubridate::floor_date(tr[1], unit = "hour")
        tr[2] <- lubridate::ceiling_date(tr[2], unit = "hour")
      } else if(i == 180) {
        tr[1] <- lubridate::floor_date(tr[1], unit = "3 hours")
        tr[2] <- lubridate::ceiling_date(tr[2], unit = "3 hours")
      } else if(i == 360) {
        tr[1] <- lubridate::floor_date(tr[1], unit = "6 hours")
        tr[2] <- lubridate::ceiling_date(tr[2], unit = "6 hours")
      } else if(i == 720) {
        tr[1] <- round_6(tr[1])
        tr[2] <- round_6(tr[2])
      } else if(i == 1440) {
        tr[1] <- lubridate::floor_date(tr[1], unit = "24 hours")
        tr[2] <- lubridate::ceiling_date(tr[2], unit = "24 hours")
      }
      if(tr[1] == tr[2]) tr[2] <- tr[1] + i*60
    })
    return(tr)
  }), debounce_int)

  time_range <- reactive({
    if(ready(time_range_d())) return(time_range_d()) else return(lubridate::with_tz(c(min(t()$times), max(t()$times)), tz = t()$tz))
  })

  instant_range <- reactive({
    lubridate::seconds(interval()*60/2)
  })

  # What is the time span of the data in hours/min/weeks etc.?
  data_range <- eventReactive(time_range(), {
    if(verbose) cat("  Data range\n")
    d <- t()$times[t()$times >= time_range()[1] & t()$times <= time_range()[2]]
    if(length(d) == 0) d <- time_range()
    as.numeric(difftime(max(d), min(d), units = "min"))
  })

  anim_speed_d <- debounce(reactive({input$anim_speed}), debounce_int)
  anim_speed <- reactive({if(ready(anim_speed_d())) return(anim_speed_d()) else return(50)})

  breaks <- reactive({
    req(interval_selection(data_range()) <= interval())

    req(lubridate::interval(time_range()[1] + interval()*60, time_range()[2] - interval()*60) %within% lubridate::interval(t()$start, t()$end)) #Make sure time range of data matches UIs (for when switching datasets) within the interval range

    if(verbose) cat("  Breaks\n")

    breaks <- seq(time_range()[1], time_range()[2], by = paste(interval(), "min"))
    if(max(breaks) < max(t()$times)) breaks <- seq(time_range()[1], time_range()[2] + instant_range()*2, by = paste(interval(), "min"))
    return(breaks)
  })

  return(c(interval = interval,
           instant_range = instant_range,
           time_range = time_range,
           anim_speed = anim_speed,
           breaks = breaks,
           tz = reactive({t()$tz}),
           tz_offset = reactive({t()$tz_offset})))
}

# Advanced Animation Controls -------------------------------------------------------
mod_UI_maps_advanced <- function(id) {

  ns <- NS(id)

  tagList(
      radioButtons(ns("type"), label = "Summary over time",
                   choices = c("Cumulative" = "cumulative", "Instant" = "instant"), inline = TRUE),
      uiOutput(ns("UI_animal_id")),
      radioButtons(ns("summary"),
                    label = "Summary type",
                    choices = c("Total sum" = "sum", "Average sum per individual" = "sum_indiv"))
  )
}


mod_maps_advanced <- function(input, output, session, samples, debounce_int, verbose = FALSE) {

  ns <- session$ns

  # UIs
  animal_id <- debounce(reactive({input$animal_id}), debounce_int)
  #animal_id <- reactive({if(ready(animal_id_d())) return(animal_id_d()) else return("all")})

  type <- debounce(reactive({input$type}), debounce_int)
  #type <- reactive({if(ready(type_d())) return(type_d()) else return("cumulative")})

  summary <- debounce(reactive({input$summary}), debounce_int)
  #summary <- reactive({if(ready(summary_d())) return(summary_d()) else return("sum")})

  # Animal ID selection
  output$UI_animal_id <- renderUI({
    labels <- as.character(samples()$animal_id)
    names(labels) <- paste0(samples()$animal_id, " (", samples()$move, " mv; ", samples()$presence, " fd)")
    labels <- c("All" = "all", labels)
    selectInput(ns("animal_id"), label = "Select Individual",
                choices = labels)
  })

  ## Toggle summary buttons
  observeEvent(animal_id(), {
    shinyjs::toggleState(selector = "input[type = 'radio'][value = 'sum_indiv']", condition = animal_id() == "all")
    if(animal_id() != "all" && summary() != "sum") updateRadioButtons(session, "summary", selected = "sum")
  })

  return(c(type = type,
           animal_id = animal_id,
           summary = summary))
}


# Time Figure -------------------------------------------------------
mod_UI_maps_time <- function(id, type = "the RFID logger") {

  ns <- NS(id)

  tagList(
    tags$style(HTML(paste0(
    "div#", ns("plot_time")," {
      text-align: center;
      }"))),
    tags$style(HTML(paste0(
      "div#", ns("plot_time")," img {
      max-width: 100%;
      }"))),
    tags$style(HTML(paste0(
      "div#", ns("UI_time")," {
      padding-left:30px;
      width: 550px;
      max-width: 100%;
      display: block;
      margin-left: auto;
      margin-right: auto;
      }"))),
    div(
           fluidRow(uiOutput(ns("UI_time")), style = "text-align: center;"),
           fluidRow(div(plotOutput(ns("plot_time"), height = "100%"),
                        style = "height: 200px")),
           fluidRow(div(
             strong("Note that times are in Local Standard Time (no DST)"), br(),
             strong("Colours represent ", type), style = "text-align: center;")),
           style = "text-align: center;")
  )
}

#' @import shiny
mod_maps_time <- function(input, output, session, controls, events, verbose = FALSE) {

  ns <- session$ns

  output$UI_time <- renderUI({
    req(controls$breaks(), controls$tz())
    req(controls$instant_range(), controls$interval(), controls$anim_speed())
    if("try-error" %in% class(try(controls$time_range(), silent = TRUE))) {
      tr <- with_tz(c(min(controls$breaks()), max(controls$breaks())), controls$tz())
    } else {
      tr <- controls$time_range()
    }
    isolate({
      if(verbose) cat("UI - Instant\n")
      # Add + controls$instant_range() to shift 'instant' to middle of block.
      sliderInput(ns("instant"), "Instant",
                  min = tr[1] + controls$instant_range(),
                  max = tr[2] + controls$instant_range(),
                  value = tr[1] + controls$instant_range(),
                  step = 60 * controls$interval()[1],
                  timezone = controls$tz_offset(),
                  animate = animationOptions(interval = 500 * (1 - (controls$anim_speed()/100)) + 0.1, loop = FALSE),
                  width = "520px")
    })
  })

  ## Convert to proper tz
  instant <- reactive({
    req(input$instant)
    isolate({
      if(verbose) cat("Instant\n")
      lubridate::with_tz(round.POSIXt(input$instant, units = "secs") - controls$instant_range(), tz = isolate(controls$tz()))
    })
  })

  # Time figure
  g_time <- eventReactive(events(), {
    req(events(), controls$instant_range())
    if("try-error" %in% class(try(controls$time_range(), silent = TRUE))) {
      l <- with_tz(c(min(controls$breaks()), max(controls$breaks())), controls$tz())
    } else {
      l <- controls$time_range()
    }
    isolate({
      if(verbose) cat("Figure - Events\n")
      if(length(unique(events()$type)) > 8) lp <- "none" else lp = "bottom"

      ## Shift start of block time to mid point of interval:
      d <- dplyr::mutate(events(), block = block + controls$instant_range()) %>%
        tidyr::complete(block, type, fill = list(n = 0))

      ## Get limits
      l[2] <- l[2] + controls$interval()*60
      l <- l + c(-0.25, 0.25)* controls$interval()*60

      ## Get breaks
      y <- seq(min(l), max(l), length.out = 8)
      b <- round(difftime(y[2], y[1])) %>%
        paste(units(.))

      ggplot2::ggplot(data = d, ggplot2::aes(x = block, y = n, fill = type)) +
        ggplot2::theme_bw() +
        ggplot2::theme(legend.position = lp) +
        ggplot2::labs(x = "Time", y = "Total # of events", fill = "") +
        ggplot2::scale_y_continuous(expand = c(0,0)) +
        ggplot2::scale_x_datetime(labels = scales::date_format("%Y %b %d\n%H:%M", tz = controls$tz()),
                                  limits = l,
                                  date_breaks = b) +
        ggplot2::geom_bar(stat = "identity",
                          width = as.numeric(controls$instant_range()),
                          position = "dodge")
    })
  })

  output$plot_time <- renderPlot({
    req(g_time())
    g_time()
  }, height = 200, width = 625)

  return(instant = instant)
}

# Sunrise overlay -------------------------------------------------------
mod_UI_maps_sunrise <- function(id) {
  ns <- NS(id)
  tagList(
    radioButtons(ns("sunrise"), "Show sunrise/sunset?",
                 choices = list("Yes" = TRUE, "No" = FALSE),
                 selected = FALSE, inline = TRUE)
  )
}


#' @import shiny
mod_maps_sunrise <- function(input, output, session, instant, controls, debounce_int, verbose = FALSE) {

  ns <- session$ns
  values <- reactiveValues()

  sunrise_d <- debounce(reactive({input$sunrise}), debounce_int)
  sunrise <- reactive({if(ready(sunrise_d())) return(input$sunrise) else return(FALSE)})

  ## Add sunrise sunset
  observeEvent(instant(), {
    req(instant(), sunrise() == TRUE)
    leafletProxy(ns("map")) %>%
      addTerminator(time = as.POSIXct(with_tz(instant() + controls$instant_range(), "UTC")),
                    layerId = "sun",
                    group = "Sunrise/Sunset")# %>%
      #removeShape(layerId = paste0("set-", values$time_prev))
    #values$time_prev <- instant()
  }, priority = 100)

  # Get rid of sunrise if radio unselected
  observeEvent(sunrise(), {
    req(sunrise() == FALSE)
    leafletProxy(ns("map")) %>%
      clearGroup(group = "Sunrise/Sunset")
  })

  # Omit option to show sunrise if 24h selected
  observeEvent(controls$interval(), {
    shinyjs::toggleState(id = "sunrise", condition = controls$interval() < 1440) #enable below 24hr
    if(controls$interval() == 1440) updateRadioButtons(session, inputId = "sunrise", selected = FALSE)
  })
}

# Actual leaflet map -------------------------------------------------------
mod_UI_maps_leaflet <- function(id) {
  ns <- NS(id)
  tagList(
    fluidRow(leafletOutput(ns("map"), height = 600))
  )
}

# Map_leaflet Server
#' @import shiny
mod_maps_leaflet <- function(input, output, session, data_instant, data_total, summary, palette = NULL, verbose = FALSE) {

  ns <- session$ns

  values <- layers <- reactiveValues()

  ## Data limits for scales
  lim <- reactive({
    req(data_total())
    lapply(data_total(), function(x) {
      col <- c("n", "amount", "path_use")[c("n", "amount", "path_use") %in% names(x$sub[[1]])]
      sort(unique(unlist(do.call('rbind', x$sub)[, col], use.names = FALSE)))
    })
  })

  ## Data loggers
  loggers <- reactive({
    req(data_total())
    unique(do.call('rbind', lapply(data_total(), function(x) unique(do.call('rbind', x$sub)[, c("logger_id", "lat", "lon")]))))
  })

  move_paths <- reactive({
    req(data_total())
    unlist(unique(do.call('rbind', data_total()$movements$sub)[, c("move_path")]), use.names = FALSE)
  })

  ## Palettes
  pal <- reactive({
    req(lim)
    l <- lim()[sapply(lim(), length) > 0]
    lapply(l, function(x) {
      if(!is.null(x)){
        vals <- x
        #if(max(vals) == 1) vals <- 1:5
        if(length(vals) == 1) vals <- sort(vals * c(0.5, 1, 1.5))
        if(is.null(palette)) palette <- grDevices::colorRampPalette(c("yellow","orange", "red"))
        leaflet::colorNumeric(palette = palette(15), domain = vals)
      }
    })
  })

  ## Render Base Map
  output$map <- renderLeaflet({
    req(lim(), loggers())
    validate(need(nrow(loggers()) > 0, "No data to summarize, consider a larger time range"))

    groups <- stringr::str_to_title(names(lim()))
    if(nrow(loggers()) < 2) minZoom <- 18 else minZoom <- NULL
    map_leaflet_base(locs = loggers(), minZoom = minZoom) %>%
      leaflet::addScaleBar(position = "bottomright") %>%
      leaflet::addLayersControl(baseGroups = c("Satellite", "Terrain", "Open Street Map", "Black and White"),
                                overlayGroups = c("Loggers", "Sunrise/Sunset", groups),
                                options = leaflet::layersControlOptions(collapsed = TRUE))
  })

  ## Create legends for map
  observe({
    req(pal(), "map_bounds" %in% names(input))
    isolate({
      leafletProxy(ns("map")) %>% clearGroup("Legends")
      lapply(names(pal()), function(a) {
        if(a == "presence") {
          title = "Presence"
          l <- labelFormat(suffix = " min")
        }
        if(a == "movements") {
          title = "Movements"
          l <- labelFormat()
        }
        if(summary() == "sum") title <- paste(title, "<br>(Total)")
        if(summary() == "sum_indiv") title <- paste(title, "<br>(Mean total)")
        #if(summary() == "total_indiv") title <- paste(title, "<br>(# Individuals)")
        vals <- lim()[[a]]
        if(length(vals) == 1) vals <- sort(vals * c(0.5, 1, 1.5))
        leaflet::leafletProxy(ns("map")) %>%
          leaflet::addLegend(title = title,
                             position = 'topright',
                             pal = pal()[[a]],
                             values = vals,
                             bins = 5,
                             opacity = 1,
                             labFormat = l,
                             layerId = paste0("legend_", a))
      })
    })
  })

  ## Add points to map
  observe({
    req(data_instant(), lim(), pal())

    if("visits" %in% names(data_instant())){
      if(nrow(data_instant()) > 0){
        leaflet::leafletProxy(ns("map")) %>%
          leaflet::clearGroup(group = "Visits") %>%
          presence_markers(data = data_instant(), p_scale = 1,
                           p_pal = pal()$visits, p_title = "Visits",
                           val_min = min(lim()$visits), val_max = max(lim()$visits))
      } else {
        leaflet::leafletProxy(ns("map")) %>% leaflet::clearGroup(group = "Visits")
      }
    }

    if("movements" %in% names(data_instant())) {
      if(!compare_data(values$m_old, data_instant()$movements)){
        if(!is.null(data_instant()$movements) && nrow(data_instant()$movements) > 0) {
          temp <- data_instant()$movements %>%
            dplyr::arrange(path_use)
          for(move_path in unique(temp$move_path)) {
            temp2 <- temp[temp$move_path == move_path, ]
            leaflet::leafletProxy(ns("map"), deferUntilFlush = FALSE) %>%
              path_lines(data = temp2, m_pal = pal()$movements,
                         m_scale = 1, m_title = "Movements",
                         val_min = min(lim()$movements),
                         val_max = max(lim()$movements),
                         layerId = as.character(temp2$move_path[1]))
          }
          leafletProxy(ns("map"), deferUntilFlush = FALSE) %>%
            removeShape(layerId = as.character(move_paths()[!(move_paths() %in% temp$move_path)]))
        } else {
          leafletProxy(ns("map")) %>% removeShape(layerId = as.character(move_paths()))
        }
        values$m_old <- data_instant()$movements
      }
    }

    if("presence" %in% names(data_instant())) {
      if(!compare_data(values$f_old, data_instant()$presence)){
        if(!is.null(data_instant()$presence) && nrow(data_instant()$presence) > 0){
          leafletProxy(ns("map"), deferUntilFlush = FALSE) %>%
            presence_markers(data = data_instant()$presence,
                        p_scale = 1, p_pal = pal()[['presence']],
                        p_title = "Presence",
                        val_min = min(lim()$presence),
                        val_max = max(lim()$presence),
                        layerId = as.character(data_instant()$presence$logger_id)) %>%
            removeMarker(layerId = as.character(loggers()$logger_id[!(loggers()$logger_id %in% data_instant()$presence$logger_id)]))
        } else {
          leafletProxy(ns("map")) %>% removeMarker(layerId = as.character(loggers()$logger_id))
        }
        values$f_old <- data_instant()$presence
      }
    }
  })
}

# Data Prep -------------------------------------------------------
#' @import shiny
mod_maps_data <- function(input, output, session, controls, instant, data, verbose = FALSE) {
  data_instant <- reactive({
    req(instant(), controls$interval(), data_instant())
    data_instant() %>%
      dplyr::filter(block >= instant(), block < instant() + 60 * controls$interval())
  })
  return(data_instant)
}

# Extra functions -------------------------------------------------------
prep_presence <- function(x, y, type = "cumulative", summary = "sum") {
  if(type == "cumulative") x <- x[x$block <= y$block[1], ] else if(type == "instant") x <- x[x$block == y$block[1], ]

  x <- x %>%
    dplyr::group_by(logger_id, lat, lon) %>%
    dplyr::summarize(amount = sum(amount)) %>%
    dplyr::ungroup()

  if(nrow(x) > 0) x <- dplyr::mutate(x,  block = y$block[1])
  return(x)
}

prep_movements <- function(x, y, type = "cumulative", summary = "sum") {
    if(type == "cumulative") x <- x[x$block <= y$block[1], ] else if(type == "instant") x <- x[x$block == y$block[1], ]
    x <- x %>%
      dplyr::group_by(move_path, logger_id, lat, lon) %>%
      dplyr::summarize(path_use = sum(path_use)) %>%
      dplyr::ungroup()
    if(nrow(x) > 0) x <- dplyr::mutate(x, block = y$block[1])
  return(x)
}

compare_data <- function(data1, data2) {
  identical(data1[, !(names(data1) %in% "block")], data2[, !(names(data2) %in% "block")])
}
