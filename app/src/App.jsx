import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { ThemeProvider } from "./theme/ThemeContext.jsx";
import HomeLayout from "./pages/HomeLayout.jsx";
import Dashboard from "./pages/Dashboard.jsx";
import Accounts from "./pages/Accounts.jsx";
import Subscribe from "./pages/Subscribe.jsx";
import Tree from "./pages/Tree.jsx";
import Wallet from "./pages/Wallet.jsx";
import Blog from "./pages/Blog.jsx";

export default function App() {
  return (
    <ThemeProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Navigate to="/dashboard" replace />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/account" element={<Accounts />} />
          <Route path="/subscribe" element={<Subscribe />} />
          <Route path="/tree" element={<Tree />} />
          <Route path="/wallet" element={<Wallet />} />
          {/* Background variants render the same layout; the switcher sets the mode. */}
          <Route path="/home-video" element={<HomeLayout />} />
          <Route path="/home-particles" element={<HomeLayout />} />
          <Route path="/home-bgcolor" element={<HomeLayout />} />
          <Route path="/blog" element={<Blog />} />
          <Route path="*" element={<Navigate to="/dashboard" replace />} />
        </Routes>
      </BrowserRouter>
    </ThemeProvider>
  );
}
