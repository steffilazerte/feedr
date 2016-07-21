## Animated map - UI
#' @import shiny
#' @import magrittr
#' @export
mod_UI_map_animate <- function(id) {
  # Create a namespace function using the provided id
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
      "div#", ns("UI_anim_time")," {
      padding-left:30px;
      width: 550px;
      max-width: 100%;
      display: block;
      margin-left: auto;
      margin-right: auto;
      }"))),
    column(4,
           h1("Data"),
           radioButtons(ns("anim_type"), "Show data by:",
                        choices = c("Total no. visits" = "t_visits",
                                    "Avg. visits per bird" = "b_visits",
                                    "Total no. birds" = "t_birds")),
           h1("Animation"),
           sliderInput(ns("anim_speed"), "Speed",
                       min = 0, max = 100,
                       post = "%",
                       value = 50),
           sliderInput(ns("anim_interval"), "Interval",
                       min = 1,
                       max = 24,
                       value = 1,
                       step = 1,
                       post = " hour(s)")
    ),
    column(8,
           fluidRow(leafletOutput(ns("map"), height = 600)),
           div(
             fluidRow(uiOutput(ns("UI_anim_time")), style = "text-align: center;"),
             fluidRow(div(plotOutput(ns("plot_time"), height = "100%"), style = "height: 150px")),
             fluidRow(div(
               strong("Note that times are in Local Standard Time (no DST)"), br(),
               strong("Colours represent 'Reader'"), style = "text-align: center;")),
             style = "text-align: center;")
    )
  )
}

# Module server function
#' @import shiny
#' @import magrittr
#' @import leaflet
#' @export
mod_map_animate <- function(input, output, session, v) {

  ns <- session$ns
  values <- reactiveValues()

  ## Palette
  pal <- colorRampPalette(c("yellow","orange", "red"))

  # Fix time zone to LOOK like local non-DST, but assigned UTC (for timezone slider)
  v <- v %>%
    dplyr::mutate(start = lubridate::with_tz(start, tzone = tz_offset(attr(v$start, "tzone"), tz_name = TRUE)),
                  end = lubridate::with_tz(end, tzone = tz_offset(attr(v$end, "tzone"), tz_name = TRUE)),
                  day = as.Date(start))

  #lubridate::tz(v$start) <- "UTC"
  #lubridate::tz(v$end) <- "UTC"

  start <- lubridate::floor_date(min(v$start), unit = "hour")
  end <- lubridate::ceiling_date(max(v$start), unit = "hour")

  # Time slider
  output$UI_anim_time <- renderUI({
    req(input$anim_speed, input$anim_interval)
    tz <- tz_offset(attr(v$start, "tzone"))
    if(tz >=0) tz <- paste0("+", sprintf("%02d", abs(tz)), "00") else tz <- paste0("-", sprintf("%02d", abs(tz)), "00")
    sliderInput(ns("anim_time"), "Time",
                min = start,
                max = end,
                value = start,
                step = 60 * 60 * input$anim_interval,
                timezone = tz,
                animate = animationOptions(interval = 500 * (1 - (input$anim_speed/100)) + 50, loop = TRUE),
                width = "520px")
  })

  ## Convert to proper tz
  anim_time <- reactive({
    req(input$anim_time)
    lubridate::with_tz(input$anim_time, lubridate::tz(v$start))
  })


  ## Break visits into blocks of time depending on animation interval
  v_block <- reactive({
    req(input$anim_interval)
    int_start <- seq(start, end - input$anim_interval * 60 * 60, by = paste(input$anim_interval, "hour"))
    int_end <- seq(start + input$anim_interval * 60 * 60, end, by = paste(input$anim_interval, "hour"))
    ## Add to end if not even
    if(length(int_end) != end) {
      int_start <- c(int_start, int_end[length(int_end)])
      int_end <- c(int_end, end)
    }
    v_block <- v %>%
      dplyr::bind_cols(data.frame(block = sapply(v$start, FUN = function(x) which(x >= int_start & x < int_end)))) %>%
      dplyr::bind_cols(data.frame(block_time = int_start[.$block]))

  })

  ## Get total data sets depending on options
  p_total <- reactive({
    req(input$anim_type)
    withProgress({
      if(input$anim_type == "t_visits") {
        #Total number of visits
        p_total <- v_block() %>%
          dplyr::group_by(feeder_id, lat, lon, block, block_time, add = TRUE) %>%
          dplyr::summarize(n = length(start))
      } else if(input$anim_type == "b_visits") {
        #Average number of visits per bird
        p_total <- v_block() %>%
          dplyr::group_by(feeder_id, lat, lon, species, bird_id, block, block_time, add = TRUE) %>%
          dplyr::summarize(n = length(start)) %>%
          dplyr::group_by(feeder_id, lat, lon, block, block_time) %>%
          dplyr::summarize(n = mean(n))
      } else if(input$anim_type == "t_birds") {
        #Total number of birds
        p_total <- v_block() %>%
          dplyr::group_by(feeder_id, lat, lon, block, block_time, add = TRUE) %>%
          dplyr::summarize(n = length(unique(bird_id)))
      }
    }, message = "Calculating intervals")
    p_total
  })

  ## Filter points by time
  p <- reactive({
    req(anim_time(), input$anim_interval)
    p_total() %>% dplyr::filter(block_time >= anim_time(), block_time < anim_time() + 60 * 60 * input$anim_interval)
  })

  ## Render Base Map
  output$map <- renderLeaflet({
    req(input$anim_type, p_total())

    if(max(p_total()$n) == 1) vals <- 1:5 else vals <- 1:max(p_total()$n)
    pal <- colorNumeric(palette = pal(max(vals)),
                        domain = vals)

    map_leaflet_base(locs = unique(v[, c("feeder_id", "lat", "lon")])) %>%
      addScaleBar(position = "bottomright") %>%
      addLayersControl(baseGroups = c("Satellite", "Terrain", "Open Street Map", "Black and White"),
                       overlayGroups = c("Readers", "Sunset/Sunrise", "Visits"),
                       options = layersControlOptions(collapsed = FALSE)) %>%
      addLegend(title = "Legend",
               position = 'topright',
               pal = pal,
               values = vals,
               bins = 5,
               opacity = 1,
               layerId = "legend")
  })

  ## Add Legends to Animated Map
  observe({
    req(input$anim_type, p(), p_total())
    if(max(p_total()$n) == 1) vals <- 1:5 else vals <- 1:max(p_total()$n)
    pal <- colorNumeric(palette = pal(max(vals)),
                        domain = vals)

    leafletProxy(ns("map")) %>%
      addLegend(title = "Legend",
                         position = 'topright',
                         pal = pal,
                         values = vals,
                         bins = 5,
                         opacity = 1,
                         layerId = "legend")
  })

  ## Add points to animated map
  observe({
    req(p(), p_total())

    if(max(p_total()$n) == 1) vals <- 1:5 else vals <- 1:max(p_total()$n)
    pal <- colorNumeric(palette = pal(max(vals)),
                        domain = vals)

    if(nrow(p()) > 0){
      leafletProxy(ns("map")) %>%
        clearGroup(group = "Visits") %>%
        addCircleMarkers(data = p(), lat = ~lat, lng = ~lon, group = "Visits",
                                  stroke = FALSE,
                                  fillOpacity = 1,
                                  radius = 50,
                                  fillColor = ~pal(n),
                                  popup = ~htmltools::htmlEscape(as.character(round(n, 1))))
    } else {
      leafletProxy(ns("map")) %>% clearGroup(group = "Visits")
    }
  }, priority = 50)

  ## Add sunrise sunset
  observeEvent(anim_time(), {
    req(anim_time(), input$anim_interval)
    leafletProxy(ns("map")) %>%
      addTerminator(time = anim_time(),
                    layerId = paste0("set-", anim_time()),
                    group = "Sunrise/Sunset") %>%
      removeShape(layerId = paste0("set-", values$time_prev))
    values$time_prev <- anim_time()
  }, priority = 100)

  ## Time figure
  g_time <- eventReactive(p_total(), {
    lab <- ifelse(input$anim_type == "t_visits", "Total no. visists", ifelse(input$anim_type == "b_visits", "Avg. visits per bird", "Total no. birds"))
    lim <- c(start, ifelse(max(p_total()$block_time) + input$anim_interval * 60 * 60 > end, max(p_total()$block_time) + input$anim_interval * 60 * 60, end))
    g_time <- ggplot2::ggplot(data = p_total()) +
      ggplot2::theme_bw() +
      ggplot2::theme(legend.position = "none") +
      ggplot2::labs(x = "Time", y = lab) +
      ggplot2::scale_y_continuous(expand = c(0,0)) +
      ggplot2::scale_x_datetime(labels = scales::date_format("%Y %b %d\n%H:%M", tz = lubridate::tz(v$start)))
                                #limits = lim,
                                #breaks = seq(start, end, length.out = 5),
                                #expand = c(0,0))

      g_time <- g_time + ggplot2::geom_bar(stat = "identity", ggplot2::aes(x = block_time, y = n, fill = feeder_id)) +
        ggplot2::labs(fill = "Reader")

    g_time
  })

  output$plot_time <- renderPlot({
    g_time()# + annotate("rect", xmin = anim_time()[1], xmax = anim_time()[1] + 60 * 60 * input$anim_interval, ymin = -Inf, ymax = +Inf, alpha = 0.5)
  }, height = 150, width = 550)
}