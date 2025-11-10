package edu.lab3.client;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.resilience4j.bulkhead.Bulkhead;
import io.github.resilience4j.bulkhead.BulkheadRegistry;
import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.reactor.bulkhead.operator.BulkheadOperator;
import io.github.resilience4j.reactor.circuitbreaker.operator.CircuitBreakerOperator;
import io.github.resilience4j.timelimiter.TimeLimiter;
import io.github.resilience4j.timelimiter.TimeLimiterRegistry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.time.Duration;

@RestController
public class CircuitBreakerController {

  private final WebClient webClient;
  private final String backendUrl;
  private final CircuitBreaker circuitBreaker;
  private final Bulkhead bulkhead;
  private final TimeLimiter timeLimiter;

  public CircuitBreakerController(WebClient webClient,
                                  @Value("${backend.cburl:http://backend:8081/circuitbreaker}") String backendUrl,
                                  CircuitBreakerRegistry cbRegistry,
                                  BulkheadRegistry bhRegistry,
                                  TimeLimiterRegistry tlRegistry) {
    this.webClient = webClient;
    this.backendUrl = backendUrl;
    this.circuitBreaker = cbRegistry.circuitBreaker("backendService");
    this.bulkhead = bhRegistry.bulkhead("backendService");
    this.timeLimiter = tlRegistry.timeLimiter("backendService");
  }

  @GetMapping("/circuitbreaker")
  public Mono<ResponseEntity<PingResult>> circuitbreaker(@RequestParam(required = false) Integer failPct,
                                                         @RequestParam(required = false) Integer delayMs) {
      long t0 = System.nanoTime();
      String backend = backendUrl;
      if (failPct != null) {
          backend += "?failPct=" + failPct;
      } else if (delayMs != null) {
          backend += "?delayMs=" + delayMs;
      }
      return webClient.get()
              .uri(backend)
              .retrieve()
              .onStatus(HttpStatusCode::isError, resp ->
                      resp.bodyToMono(String.class).defaultIfEmpty("")
                              .flatMap(body -> Mono.error(new UpstreamException(resp.statusCode(), body)))
              )
              .bodyToMono(String.class)

              // (1) optional: cap concurrency early to protect the client
              .transformDeferred(BulkheadOperator.of(bulkhead))

              // (2) keep your client-side timeout
              .timeout(Duration.ofSeconds(2))

              // (3) place the CircuitBreaker AFTER timeout so timeouts count as failures
              .transformDeferred(CircuitBreakerOperator.of(circuitBreaker))

              // (4) success mapping
              .map(body -> {
                  double elapsed = (System.nanoTime() - t0) / 1e9;
                  return ResponseEntity.ok(
                          new PingResult("ok", elapsed, tryParseJson(body), backendUrl)
                  );
              })

              // (5) CB OPEN → fast-fail / fallback
              .onErrorResume(CallNotPermittedException.class, ex -> {
                  double elapsed = (System.nanoTime() - t0) / 1e9;
                  return Mono.just(ResponseEntity
                          .status(HttpStatus.SERVICE_UNAVAILABLE)
                          .body(new PingResult("fallback", elapsed,
                                  "circuit open", backendUrl)));
              })

              // (6) upstream 4xx/5xx mapped by your onStatus handler
              .onErrorResume(UpstreamException.class, ex -> {
                  double elapsed = (System.nanoTime() - t0) / 1e9;
                  return Mono.just(ResponseEntity
                          .status(ex.status())
                          .body(new PingResult("error", elapsed, ex.body(), backendUrl)));
              })

              // (7) everything else (DNS/connect/timeout, etc.)
              .onErrorResume(Exception.class, ex -> {
                  double elapsed = (System.nanoTime() - t0) / 1e9;
                  return Mono.just(ResponseEntity
                          .status(HttpStatus.BAD_GATEWAY)
                          .body(new PingResult("error", elapsed, ex.getMessage(), backendUrl)));
              });
  }

    static Object tryParseJson(String s) {
        try { return new ObjectMapper().readTree(s); }
        catch (Exception e) { return s; }
    }
}
