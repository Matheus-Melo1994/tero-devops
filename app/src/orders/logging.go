package main

import (
	"log/slog"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

var safeRequestID = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

func configureLogging() {
	handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{ReplaceAttr: func(_ []string, a slog.Attr) slog.Attr {
		switch a.Key {
		case slog.TimeKey:
			return slog.Time("timestamp", a.Value.Time().UTC())
		case slog.MessageKey:
			a.Key = "message"
		case slog.LevelKey:
			a.Value = slog.StringValue(strings.ToLower(a.Value.String()))
		}
		return a
	}})
	slog.SetDefault(slog.New(handler).With("service", "orders"))
}

func requestLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		route := c.FullPath()
		if route == "" {
			route = "unmatched"
		}
		args := []any{"method", c.Request.Method, "route", route, "status", c.Writer.Status(), "duration_ms", float64(time.Since(start).Microseconds()) / 1000}
		if id := c.GetHeader("X-Request-ID"); safeRequestID.MatchString(id) {
			args = append(args, "request_id", id)
		}
		if c.Writer.Status() >= http.StatusInternalServerError {
			slog.Error("HTTP request", args...)
		} else {
			slog.Info("HTTP request", args...)
		}
	}
}

func recoveryLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if recovered := recover(); recovered != nil {
				slog.Error("Unhandled request error", "error_type", "panic")
				c.AbortWithStatus(http.StatusInternalServerError)
			}
		}()
		c.Next()
	}
}
