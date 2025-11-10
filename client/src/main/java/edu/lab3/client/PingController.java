package edu.lab3.client;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.resilience4j.bulkhead.Bulkhead;
import io.github.resilience4j.bulkhead.BulkheadRegistry;
import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.timelimiter.TimeLimiter;
import io.github.resilience4j.timelimiter.TimeLimiterRegistry;
import org.springframework.beans.factory.annotation.Value;
import io.github.resilience4j.reactor.circuitbreaker.operator.CircuitBreakerOperator;
import io.github.resilience4j.reactor.bulkhead.operator.BulkheadOperator;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.time.Duration;

import static edu.lab3.client.CircuitBreakerController.tryParseJson;

@RestController
public class PingController {

  private final WebClient webClient;
  private final String backendUrl;

  public PingController(WebClient webClient,
                        @Value("${backend.url:http://backend:8081/work}") String backendUrl,
                        CircuitBreakerRegistry cbRegistry,
                        BulkheadRegistry bhRegistry,
                        TimeLimiterRegistry tlRegistry) {
    this.webClient = webClient;
    this.backendUrl = backendUrl;
  }

  @GetMapping("/")
  public Mono<String> root() {
    return Mono.just("client: hello");
  }

  @GetMapping("/health")
  public String health() {
    return "OK";
  }

  @GetMapping("/ping")
  public Mono<ResponseEntity<PingResult>> ping() {
      long t0 = System.nanoTime();

      return webClient.get()
              .uri(backendUrl)
              .retrieve()
              .onStatus(HttpStatusCode::isError,
                      resp -> resp.bodyToMono(String.class)
                              .defaultIfEmpty("")
                              .flatMap(body -> Mono.error(new UpstreamException(resp.statusCode(), body))) )
              .bodyToMono(String.class)
              .timeout(Duration.ofSeconds(2))
      // client-side timeout
      .map(body -> { double elapsed = (System.nanoTime() - t0) / 1e9;
          return ResponseEntity.ok( new PingResult("ok", elapsed, tryParseJson(body), backendUrl) );
      })
              .onErrorResume(UpstreamException.class, ex -> { double elapsed = (System.nanoTime() - t0) / 1e9;
                  return Mono.just(ResponseEntity .status(ex.status())
                          .body(new PingResult("error", elapsed, ex.body(), backendUrl))); })
              .onErrorResume(Exception.class, ex -> { double elapsed = (System.nanoTime() - t0) / 1e9;
                  return Mono.just(ResponseEntity .status(HttpStatus.BAD_GATEWAY)
                          // connect refused, DNS, timeout, etc.
                          .body(new PingResult("error", elapsed, ex.getMessage(), backendUrl)));
              });
  }
}
