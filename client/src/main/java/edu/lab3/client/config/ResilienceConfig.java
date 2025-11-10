package edu.lab3.client.config;

import io.github.resilience4j.bulkhead.*;
import io.github.resilience4j.circuitbreaker.*;
import io.github.resilience4j.timelimiter.*;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

@Configuration
public class ResilienceConfig {

    @Bean
    public CircuitBreakerConfig circuitBreakerConfig() {
        return CircuitBreakerConfig.custom()
                .failureRateThreshold(50)                          // % of failures to open breaker
                .slowCallRateThreshold(50)                         // % of slow calls to count as failures
                .slowCallDurationThreshold(Duration.ofSeconds(2))   // threshold for slow calls
                .waitDurationInOpenState(Duration.ofSeconds(10))    // how long to stay OPEN before half-open
                .permittedNumberOfCallsInHalfOpenState(5)           // test calls when half-open
                .slidingWindowType(CircuitBreakerConfig.SlidingWindowType.COUNT_BASED)
                .slidingWindowSize(20)                              // # of calls in window
                .recordExceptions(
                        java.io.IOException.class,
                        java.util.concurrent.TimeoutException.class,
                        org.springframework.web.reactive.function.client.WebClientRequestException.class
                )
                .automaticTransitionFromOpenToHalfOpenEnabled(true)
                .build();
    }

    @Bean
    public CircuitBreakerRegistry circuitBreakerRegistry(CircuitBreakerConfig config) {
        return CircuitBreakerRegistry.of(config);
    }

    @Bean
    public BulkheadConfig bulkheadConfig() {
        return BulkheadConfig.custom()
                .maxConcurrentCalls(10)
                .maxWaitDuration(Duration.ZERO)
                .build();
    }

    @Bean
    public BulkheadRegistry bulkheadRegistry(BulkheadConfig config) {
        return BulkheadRegistry.of(config);
    }

    @Bean
    public TimeLimiterConfig timeLimiterConfig() {
        return TimeLimiterConfig.custom()
                .timeoutDuration(Duration.ofSeconds(3))
                .build();
    }

    @Bean
    public TimeLimiterRegistry timeLimiterRegistry(TimeLimiterConfig config) {
        return TimeLimiterRegistry.of(config);
    }
}
