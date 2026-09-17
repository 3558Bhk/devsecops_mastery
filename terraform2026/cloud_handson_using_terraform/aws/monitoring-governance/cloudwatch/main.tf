# ============================================================================
#  CloudWatch — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_cloudwatch_log_group" "app" {      # the log group
  name              = "/lab/app"                  # the group's name (a path)
  retention_in_days = 7                           # keep logs 7 days (7-3650, or Infinity)
  tags              = { app = "lab" }             # a label
}

resource "aws_cloudwatch_log_metric_filter" "errors" {   # the filter (lives in the log group)
  name           = "count-500s"                   # the filter's name
  log_group_name = aws_cloudwatch_log_group.app.name   # which log group
  pattern        = "\"status\":500"               # the literal log fragment to match

  metric_transformation {                          # what to do on a match: emit a metric point
    name      = "AppErrors"                        # the metric's name
    namespace = "lab/app"                          # the metric's namespace (a folder)
    value     = "1"                                # +1 per match
  }
}

resource "aws_sns_topic" "oncall" {              # the pager (a topic so many can subscribe)
  name = "lab-oncall"                            # the topic's name
}

resource "aws_cloudwatch_metric_alarm" "errors" {   # the alarm
  alarm_name          = "app-errors-high"         # the alarm's name
  namespace           = "lab/app"                 # the metric's namespace (same as the filter)
  metric_name         = "AppErrors"               # the metric (same as the filter)
  statistic           = "Sum"                     # sum the points in the period
  period              = 300                       # 5-minute data points
  evaluation_periods  = 1                         # 1 bad period is enough
  threshold           = 5                         # more than 5 errors…
  comparison_operator = "GreaterThanThreshold"    # …trips the alarm
  treat_missing_data  = "notBreaching"            # missing data ≠ alarm

  alarm_actions = [aws_sns_topic.oncall.arn]      # when ALARM: publish to the topic (everyone subscribed gets paged)
}

resource "aws_cloudwatch_dashboard" "lab" {      # the dashboard
  dashboard_name = "lab-dashboard"                    # the dashboard's name (v5: dashboard_name)

  # the dashboard body is JSON — one widget per metric (built with templatestring)
  dashboard_body = jsonencode({                             # the widget tree
    widgetWidth   = 24                             # full width
    widgets = [
      {
        type   = "metric"                         # a metric graph
        width  = 24                               # full width
        height = 6                                # the height
        properties = {                             # which metric to draw
          metrics = [["lab/app", "AppErrors", "Total"]]   # [namespace, name, stat]
          view    = "timeSeries"                   # a time-series view
          period  = 300                            # 5-minute resolution
        }
      }
    ]
  })
}
