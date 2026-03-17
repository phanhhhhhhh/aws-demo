package com.demo.awsdemo.controller;

import com.demo.awsdemo.dto.AuthDto;
import com.demo.awsdemo.model.User;
import com.demo.awsdemo.repository.UserRepository;
import com.demo.awsdemo.service.AuthService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;
    private final UserRepository userRepository;

    // ── Public endpoints ──────────────────────────────────────────

    @PostMapping("/auth/register")
    public ResponseEntity<?> register(@Valid @RequestBody AuthDto.RegisterRequest request) {
        try {
            AuthDto.AuthResponse response = authService.register(request);
            return ResponseEntity.status(HttpStatus.CREATED).body(response);
        } catch (RuntimeException e) {
            Map<String, String> error = new HashMap<>();
            error.put("error", e.getMessage());
            return ResponseEntity.badRequest().body(error);
        }
    }

    @PostMapping("/auth/login")
    public ResponseEntity<?> login(@Valid @RequestBody AuthDto.LoginRequest request) {
        try {
            AuthDto.AuthResponse response = authService.login(request);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, String> error = new HashMap<>();
            error.put("error", "Invalid username or password");
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(error);
        }
    }

    @GetMapping("/public/health-info")
    public ResponseEntity<?> healthInfo() {
        Map<String, Object> info = new HashMap<>();
        info.put("status", "UP");
        info.put("service", "AWS Demo - User Registration");
        info.put("version", "1.0.0");
        info.put("totalUsers", userRepository.count());
        return ResponseEntity.ok(info);
    }

    // ── Protected endpoints ───────────────────────────────────────

    @GetMapping("/users/me")
    public ResponseEntity<?> getMyProfile(Authentication authentication) {
        String username = authentication.getName();
        return userRepository.findByUsername(username)
                .map(user -> ResponseEntity.ok(toUserResponse(user)))
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/admin/users")
    public ResponseEntity<?> getAllUsers(Authentication authentication) {
        // Simple role check
        boolean isAdmin = authentication.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("ROLE_ADMIN"));
        if (!isAdmin) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("error", "Admin access required"));
        }
        List<AuthDto.UserResponse> users = userRepository.findAll()
                .stream()
                .map(this::toUserResponse)
                .collect(Collectors.toList());
        return ResponseEntity.ok(Map.of("total", users.size(), "users", users));
    }

    private AuthDto.UserResponse toUserResponse(User user) {
        return new AuthDto.UserResponse(
                user.getId(),
                user.getUsername(),
                user.getEmail(),
                user.getFullName(),
                user.getRole().name(),
                user.getCreatedAt() != null ? user.getCreatedAt().toString() : null
        );
    }
}
