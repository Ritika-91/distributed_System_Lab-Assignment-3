package edu.lab3.backend;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.security.SecureRandom;

@RestController
public class WorkController {

  private final SecureRandom rnd = new SecureRandom();

  private final double failRate = Double.parseDouble(System.getenv().getOrDefault("FAIL_RATE", "0.2"));
  private final int maxDelayMs = Integer.parseInt(System.getenv().getOrDefault("MAX_DELAY_MS", "800"));
  private final double timeoutProb = Double.parseDouble(System.getenv().getOrDefault("TIMEOUT_PROB", "0.05"));

  public static class WorkResponse {
    public String status;
    public String payload;
    public int delayMs;
    public WorkResponse(String status, String payload, int delayMs) {
      this.status = status;
      this.payload = payload;
      this.delayMs = delayMs;
    }
  }

  @GetMapping("/")
  public String root() {
    return "backend: hello";
  }

  @GetMapping("/health")
  public String health() {
    return "OK";
  }

  @GetMapping("/work")
  public ResponseEntity<?> work() throws InterruptedException {
    if (rnd.nextDouble() < timeoutProb) Thread.sleep(10_000);
    int delay = rnd.nextInt(maxDelayMs + 1);
    Thread.sleep(delay);
    if (rnd.nextDouble() < failRate) {
      return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Simulated failure");
    }
    return ResponseEntity.ok()
            .contentType(MediaType.APPLICATION_JSON)
            .body(new WorkResponse("ok", "Hello from backend", delay));
  }
}
