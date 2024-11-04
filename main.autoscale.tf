resource "azurerm_monitor_autoscale_setting" "this" {
  count               = var.autoscale_enabled ? 1 : 0
  name                = var.autoscale_setting_name
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_orchestrated_virtual_machine_scale_set.virtual_machine_scale_set.id

  dynamic "profile" {
    for_each = var.autoscale_setting.profiles
    content {
      name = profile.value.name
      capacity {
        default = profile.value.capacity.default
        minimum = profile.value.capacity.minimum
        maximum = profile.value.capacity.maximum
      }

      dynamic "rule" {
        for_each = profile.value.rules
        content {
          metric_trigger {
            metric_name = rule.value.metric_trigger.metric_name
            # metric_resource_id = rule.value.metric_trigger.metric_resource_id
            metric_resource_id = azurerm_orchestrated_virtual_machine_scale_set.virtual_machine_scale_set.id
            metric_namespace   = rule.value.metric_trigger.metric_namespace
            operator           = rule.value.metric_trigger.operator
            statistic          = rule.value.metric_trigger.statistic
            threshold          = rule.value.metric_trigger.threshold
            time_aggregation   = rule.value.metric_trigger.time_aggregation
            time_grain         = rule.value.metric_trigger.time_grain
            time_window        = rule.value.metric_trigger.time_window
          }
          scale_action {
            cooldown  = rule.value.scale_action.cooldown
            direction = rule.value.scale_action.direction
            type      = rule.value.scale_action.type
            value     = rule.value.scale_action.value
          }
        }
      }

      # Handle optional fixed_date
      dynamic "fixed_date" {
        for_each = [for fd in [profile.value.fixed_date] : fd if fd != null] # check for null
        content {
          timezone = fixed_date.value.timezone
          start    = fixed_date.value.start
          end      = fixed_date.value.end
        }
      }

      # Handle optional recurrence
      dynamic "recurrence" {
        for_each = [for rc in [profile.value.recurrence] : rc if rc != null] # check for null
        content {
          days     = recurrence.value.days
          hours    = recurrence.value.hours
          minutes  = recurrence.value.minutes
          timezone = recurrence.value.timezone
        }
      }
    }
  }

  # Handle optional notifications
  dynamic "notification" {
    for_each = [for n in [var.autoscale_setting.notification] : n if n != null] # check for null
    content {
      dynamic "email" {
        for_each = [for e in [notification.value.email] : e if e != null] # check for null
        content {
          custom_emails                         = email.value.custom_emails
          send_to_subscription_co_administrator = email.value.send_to_subscription_co_administrator
          send_to_subscription_administrator    = email.value.send_to_subscription_administrator
        }
      }
      dynamic "webhook" {
        for_each = [for w in [notification.value.webhook] : w if w != null] # check for null
        content {
          service_uri = webhook.value.service_uri
          properties  = webhook.value.properties
        }
      }
    }
  }

  # Handle optional predictive
  dynamic "predictive" {
    for_each = [for p in [var.autoscale_setting.predictive] : p if p != null] # check for null
    content {
      scale_mode      = predictive.value.scale_mode
      look_ahead_time = predictive.value.look_ahead_time
    }
  }

  tags = var.tags
}
