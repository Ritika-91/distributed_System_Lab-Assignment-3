package edu.lab3.backend;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.concurrent.ThreadLocalRandom;
@RestController
public class CircuitBreakerController
{
    @GetMapping("/circuitbreaker")
    public ResponseEntity<String> circuitbreaker(@RequestParam(required=false) Integer failPct,
                                       @RequestParam(required=false) Integer delayMs) throws Exception {
        if (delayMs != null) Thread.sleep(delayMs);
        if (failPct != null && ThreadLocalRandom.current().nextInt(100) < failPct) {
            return ResponseEntity.status(500).body("{\"error\":\"forced\"}");
        }
        return ResponseEntity.ok("{\"backend\":\"ok\"}");
    }
}
