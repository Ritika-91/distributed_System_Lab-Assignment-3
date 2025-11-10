package edu.lab3.client;

import org.springframework.http.HttpStatusCode;

final class UpstreamException extends RuntimeException {
    private final HttpStatusCode status;
    private final String body;
    UpstreamException(HttpStatusCode status, String body) { this.status = status; this.body = body; }
    HttpStatusCode status() { return status; }
    String body() { return body; }
}