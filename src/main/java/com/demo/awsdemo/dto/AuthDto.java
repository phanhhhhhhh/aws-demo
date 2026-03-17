package com.demo.awsdemo.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Data;

public class AuthDto {

    @Data
    public static class RegisterRequest {
        @NotBlank(message = "Username is required")
        @Size(min = 3, max = 50, message = "Username must be between 3-50 characters")
        private String username;

        @NotBlank(message = "Email is required")
        @Email(message = "Email format is invalid")
        private String email;

        @NotBlank(message = "Password is required")
        @Size(min = 6, message = "Password must be at least 6 characters")
        private String password;

        @Size(max = 100)
        private String fullName;
    }

    @Data
    public static class LoginRequest {
        @NotBlank(message = "Username is required")
        private String username;

        @NotBlank(message = "Password is required")
        private String password;
    }

    @Data
    public static class AuthResponse {
        private String token;
        private String username;
        private String email;
        private String role;
        private String message;

        public AuthResponse(String token, String username, String email, String role, String message) {
            this.token = token;
            this.username = username;
            this.email = email;
            this.role = role;
            this.message = message;
        }
    }

    @Data
    public static class UserResponse {
        private Long id;
        private String username;
        private String email;
        private String fullName;
        private String role;
        private String createdAt;

        public UserResponse(Long id, String username, String email,
                            String fullName, String role, String createdAt) {
            this.id = id;
            this.username = username;
            this.email = email;
            this.fullName = fullName;
            this.role = role;
            this.createdAt = createdAt;
        }
    }
}
